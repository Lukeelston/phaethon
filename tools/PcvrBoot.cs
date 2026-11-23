// The engine can block in the native OpenXR loader before any game script runs.
// Ship a small Windows entry point that can still log and bound that wait.
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using System.Text;
using System.Windows.Forms;

internal static class PcvrBoot
{
    const int AttemptMs = 35000;
    const int HeartbeatMs = 5000;
    static readonly object Sync = new object();
    static readonly Stopwatch Clock = Stopwatch.StartNew();
    static StreamWriter log;
    static string stage;
    static string lastLine;
    static bool booted;
    static bool xrFailure;

    // A user closing a stalled launcher in Task Manager must also release the
    // engine (and thus the runtime session) before launching a second copy.
    [StructLayout(LayoutKind.Sequential)]
    struct BasicLimits
    {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinWorkingSet, MaxWorkingSet;
        public uint ActiveProcesses;
        public UIntPtr Affinity;
        public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)]
    struct ExtendedLimits
    {
        public BasicLimits Basic;
        public ulong Reads, Writes, Others, ReadBytes, WriteBytes, OtherBytes;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [DllImport("kernel32", SetLastError = true)]
    static extern SafeFileHandle CreateJobObject(IntPtr security, string name);
    [DllImport("kernel32", SetLastError = true)]
    static extern bool SetInformationJobObject(SafeFileHandle job, int type, ref ExtendedLimits limits, int size);
    [DllImport("kernel32", SetLastError = true)]
    static extern bool AssignProcessToJobObject(SafeFileHandle job, IntPtr process);

    // ProcessStartInfo on .NET Framework accepts a Windows argument string.
    static string Quote(string value)
    {
        var text = new StringBuilder("\"");
        int slashes = 0;
        foreach (char ch in value)
        {
            if (ch == '\\') { slashes++; continue; }
            text.Append('\\', ch == '"' ? slashes * 2 + 1 : slashes);
            text.Append(ch);
            slashes = 0;
        }
        return text.Append('\\', slashes * 2).Append('"').ToString();
    }

    static void Record(string line)
    {
        log.WriteLine("{0:O} +{1}ms {2}", DateTime.UtcNow, Clock.ElapsedMilliseconds, line);
    }

    static void Observe(string line, bool error)
    {
        if (line == null) return;
        lock (Sync)
        {
            if (!booted)
            {
                // Native verbose messages identify the last runtime/driver operation reached.
                if (!String.IsNullOrWhiteSpace(line)) lastLine = line;
                if (line.IndexOf("OpenXR", StringComparison.OrdinalIgnoreCase) >= 0 &&
                    (error || line.IndexOf("failed", StringComparison.OrdinalIgnoreCase) >= 0 ||
                     line.IndexOf("error", StringComparison.OrdinalIgnoreCase) >= 0))
                    xrFailure = true;
                if (line.StartsWith("PCVR ") || line.StartsWith("OpenXR") || line.StartsWith("XR:")
                    || line.StartsWith("Vulkan") || line.StartsWith("Loading resource:"))
                    stage = line;
                Record(line);
                booted = line.StartsWith("VR MENU: ready") || line.StartsWith("PCVR HANDOFF:")
                    || line.StartsWith("PCVR BOOT: benchmark=true ");
            }
        }
        if (error) Console.Error.WriteLine(line); else Console.WriteLine(line);
    }

    static int Run(string[] args, int attempt)
    {
        string root = AppDomain.CurrentDomain.BaseDirectory;
        string name = Path.GetFileNameWithoutExtension(Application.ExecutablePath);
        bool source = name.Equals("PcvrSource", StringComparison.OrdinalIgnoreCase)
            && args.Length >= 2 && args[0] == "--source-engine" && Path.IsPathRooted(args[1]);
        var info = new ProcessStartInfo(source ? args[1] : Path.Combine(root, name + ".engine"));
        info.UseShellExecute = false;
        info.RedirectStandardOutput = info.RedirectStandardError = true;
        info.WorkingDirectory = root;
        // The shipping template forbids --main-pack. The .engine PE and .pck share a stem.
        info.Arguments = "--verbose " + String.Join(" ", args.Skip(source ? 2 : 0).Select(Quote));
        info.EnvironmentVariables["PHAETHON_SOURCE_BOOT"] = source ? "1" : "0";
        info.EnvironmentVariables["PHAETHON_BOOT_ATTEMPT"] = attempt.ToString();
        lock (Sync)
        {
            stage = "starting native engine and OpenXR loader";
            lastLine = "(no engine output)";
            booted = false;
            xrFailure = false;
            Record("attempt=" + attempt + " " + stage);
        }
        using (var player = new Process { StartInfo = info })
        using (var job = CreateJobObject(IntPtr.Zero, null))
        {
            var limits = new ExtendedLimits();
            limits.Basic.Flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
            if (job.IsInvalid || !SetInformationJobObject(job, 9, ref limits, Marshal.SizeOf(limits)))
                throw new Win32Exception(Marshal.GetLastWin32Error());
            player.OutputDataReceived += (sender, e) => Observe(e.Data, false);
            player.ErrorDataReceived += (sender, e) => Observe(e.Data, true);
            player.Start();
            lock (Sync) Record("native engine pid=" + player.Id);
            if (!AssignProcessToJobObject(job, player.Handle) && !player.HasExited)
            {
                var error = new Win32Exception(Marshal.GetLastWin32Error());
                player.Kill();
                player.WaitForExit();
                throw error;
            }
            var elapsed = Stopwatch.StartNew();
            player.BeginOutputReadLine();
            player.BeginErrorReadLine();
            while (!player.WaitForExit(HeartbeatMs))
            {
                lock (Sync)
                {
                    if (booted) break;
                    Record("WATCHDOG attempt=" + attempt + " waiting_at=" + stage + " last_output=" + lastLine);
                    if (elapsed.ElapsedMilliseconds < AttemptMs) continue;
                    Record("DEADLINE terminating stalled engine pid=" + player.Id);
                    job.Close();
                    break;
                }
            }
            // Wait for the game, then release any descendant holding a pipe.
            while (!player.WaitForExit(60000)) { }
            job.Close();
            player.WaitForExit();
            if (!booted && (elapsed.ElapsedMilliseconds >= AttemptMs || (xrFailure && player.ExitCode != 0)))
                return 75;
            return player.ExitCode;
        }
    }

    [STAThread]
    static int Main(string[] args)
    {
        string path = null;
        try
        {
            string folder = Path.Combine(Environment.GetEnvironmentVariable("APPDATA")
                ?? Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "ElstonWorks", "Phaethon-VR", "boot");
            Directory.CreateDirectory(folder);
            path = Path.Combine(folder, DateTime.UtcNow.ToString("yyyyMMddTHHmmss.fffffffZ")
                + "-" + Process.GetCurrentProcess().Id + ".log");
            using (log = new StreamWriter(new FileStream(path, FileMode.CreateNew, FileAccess.Write, FileShare.Read)))
            {
                log.AutoFlush = true;
                Record("process start");
                int code;
                try
                {
                    code = Run(args, 1);
                    if (code == 75)
                    {
                        Record("OpenXR retry in 1 second");
                        System.Threading.Thread.Sleep(1000);
                        code = Run(args, 2);
                    }
                }
                catch (Exception e)
                {
                    Record("launch failed at " + stage + ": " + e.Message);
                    throw;
                }
                Record("exit=" + code);
                if (code == 75 && !args.Contains("--headless"))
                    MessageBox.Show("OpenXR did not start in two attempts. Boot log:\n" + path, "Phaethon VR");
                return code;
            }
        }
        catch (Exception e)
        {
            Console.Error.WriteLine(e.Message);
            if (!args.Contains("--headless"))
                MessageBox.Show(e.Message + "\n" + path, "Phaethon VR startup");
            return 1;
        }
    }
}
