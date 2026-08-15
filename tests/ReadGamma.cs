using System;
using LumaFlux;
class ReadGamma {
    static void Main() {
        foreach (MonitorInfo m in MonitorEnum.All()) {
            Native.RampTable now = GammaEngine.Capture(m);
            Native.RampTable id = Native.RampTable.Identity();
            int maxDiff = 0;
            for (int i = 0; i < 256; i++) {
                maxDiff = Math.Max(maxDiff, Math.Abs(now.Red[i] - id.Red[i]));
                maxDiff = Math.Max(maxDiff, Math.Abs(now.Blue[i] - id.Blue[i]));
            }
            Console.Write(maxDiff + " ");
        }
    }
}
