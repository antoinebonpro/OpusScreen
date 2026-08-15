using System;
using System.Management;
using System.Threading;
using LumaFlux;

class MonitorTool
{
    static int Deviation()
    {
        int max = 0;
        foreach (MonitorInfo m in MonitorEnum.All())
        {
            Native.RampTable now = GammaEngine.Capture(m);
            Native.RampTable id = Native.RampTable.Identity();
            for (int i = 0; i < 256; i++)
                max = Math.Max(max, Math.Abs(now.Green[i] - id.Green[i]));
        }
        return max;
    }

    static int Backlight()
    {
        try
        {
            using (ManagementClass c = new ManagementClass("root\\WMI", "WmiMonitorBrightness", null))
            using (ManagementObjectCollection col = c.GetInstances())
                foreach (ManagementObject mo in col) using (mo) return Convert.ToInt32(mo["CurrentBrightness"]);
        }
        catch { }
        return -1;
    }

    static void Main(string[] args)
    {
        int seconds = args.Length > 0 ? int.Parse(args[0]) : 60;
        Console.WriteLine("temps | gamma  | retroeclairage | variation");
        Console.WriteLine("------+--------+----------------+----------");

        int lastG = -1, lastB = -1;
        for (int t = 0; t <= seconds; t++)
        {
            int g = Deviation();
            int b = Backlight();
            string note = "";
            if (lastG >= 0 && g != lastG) note += "GAMMA change ";
            if (lastB >= 0 && b != lastB) note += "RETROECLAIRAGE " + lastB + " -> " + b;
            Console.WriteLine(string.Format("{0,5} | {1,6} | {2,14} | {3}", t, g, b, note));
            lastG = g; lastB = b;
            Thread.Sleep(1000);
        }
    }
}
