using System;
using OpusScreen;

class EngineTest
{
    static int failures = 0;

    static void Check(bool cond, string what)
    {
        if (!cond) { Console.WriteLine("  ECHEC : " + what); failures++; }
    }

    static void Main()
    {
        Console.WriteLine("=== Plan de luminosite ===");
        Console.WriteLine("  B%   gamma   gain   voile   materiel  ecretage  effectif");
        double[] tests = { 5, 10, 20, 35, 50, 75, 100, 110, 125, 135, 140, 150 };
        foreach (double b in tests)
        {
            BrightnessPlan p = GammaEngine.Plan(b, true, true);
            // luminance effective au gris moyen (in = 0.5)
            double mid = Math.Pow(0.5, 1.0 / p.GammaExponent) * p.LinearGain * p.OverlayTransmission;
            Console.WriteLine(string.Format(
                "  {0,3}   {1,5:0.00}  {2,5:0.00}  {3,5:0.00}   {4,4}     {5,-5}    {6:0.000}",
                b, p.GammaExponent, p.LinearGain, p.OverlayTransmission,
                p.HardwareTarget, p.Clips ? "oui" : "non", mid));

            Check(p.OverlayAlpha <= 250, "alpha borne a 250 (B=" + b + ")");
            Check(p.GammaExponent >= 1.0, "gamma jamais < 1 (B=" + b + ")");
        }

        Console.WriteLine();
        Console.WriteLine("=== Monotonie : plus de luminosite = plus de lumiere ===");
        double prev = -1;
        bool monotone = true;
        for (double b = 5; b <= 150; b += 1)
        {
            BrightnessPlan p = GammaEngine.Plan(b, true, true);
            double mid = Math.Pow(0.5, 1.0 / p.GammaExponent) * p.LinearGain * p.OverlayTransmission;
            if (mid < prev - 1e-9) { Console.WriteLine("  rupture a B=" + b); monotone = false; }
            prev = mid;
        }
        Check(monotone, "la courbe doit etre strictement croissante de 5 a 150");
        Console.WriteLine(monotone ? "  OK, aucune rupture" : "  RUPTURE DETECTEE");

        Console.WriteLine();
        Console.WriteLine("=== Ecretage : aucun avant 135 % ===");
        for (double b = 100; b <= 150; b += 5)
        {
            BrightnessPlan p = GammaEngine.Plan(b, true, true);
            if (b <= 135) Check(!p.Clips, "pas d'ecretage a " + b + " %");
        }
        Console.WriteLine("  OK");

        Console.WriteLine();
        Console.WriteLine("=== Rampes : bornes et croissance ===");
        foreach (double b in tests)
        {
            foreach (int k in new int[] { 6500, 3400, 1900, 1200 })
            {
                BrightnessPlan p = GammaEngine.Plan(b, true, true);
                Native.RampTable r = GammaEngine.BuildRamp(p, k);
                for (int i = 1; i < 256; i++)
                {
                    Check(r.Red[i] >= r.Red[i - 1], "rouge croissant B=" + b + " K=" + k);
                    Check(r.Green[i] >= r.Green[i - 1], "vert croissant B=" + b + " K=" + k);
                    Check(r.Blue[i] >= r.Blue[i - 1], "bleu croissant B=" + b + " K=" + k);
                }
                Check(r.Red[0] == 0 && r.Green[0] == 0 && r.Blue[0] == 0, "le noir reste noir B=" + b + " K=" + k);
            }
        }
        Console.WriteLine("  OK");

        Console.WriteLine();
        Console.WriteLine("=== Neutralite : 100 % / 6500 K doit etre l'identite ===");
        {
            BrightnessPlan p = GammaEngine.Plan(100, true, true);
            Native.RampTable r = GammaEngine.BuildRamp(p, 6500);
            Native.RampTable id = Native.RampTable.Identity();
            int maxDiff = 0;
            for (int i = 0; i < 256; i++)
            {
                maxDiff = Math.Max(maxDiff, Math.Abs(r.Red[i] - id.Red[i]));
                maxDiff = Math.Max(maxDiff, Math.Abs(r.Green[i] - id.Green[i]));
                maxDiff = Math.Max(maxDiff, Math.Abs(r.Blue[i] - id.Blue[i]));
            }
            Console.WriteLine("  ecart max a l'identite : " + maxDiff + " / 65535");
            Check(maxDiff < 300, "100 %/6500 K doit etre neutre");
            Check(p.HardwareTarget == -1, "a 100 % on ne touche pas au retroeclairage");
        }

        Console.WriteLine();
        Console.WriteLine("=== Temperature : le bleu doit chuter quand ca chauffe ===");
        double prevBlue = 2;
        for (int k = 6500; k >= 1200; k -= 500)
        {
            double[] m = ColorTemp.Multipliers(k);
            Console.WriteLine(string.Format("  {0,4} K  R={1:0.000} G={2:0.000} B={3:0.000}", k, m[0], m[1], m[2]));
            Check(m[2] <= prevBlue + 1e-9, "bleu decroissant a " + k + " K");
            prevBlue = m[2];
        }
        {
            double[] m = ColorTemp.Multipliers(6500);
            Check(Math.Abs(m[0] - 1) < 0.01 && Math.Abs(m[1] - 1) < 0.01 && Math.Abs(m[2] - 1) < 0.01,
                  "6500 K doit etre exactement neutre");
        }

        Console.WriteLine();
        Console.WriteLine("=== Horloge solaire (Paris, 48.86 / 2.35) ===");
        foreach (var d in new DateTime[] {
            new DateTime(2026, 6, 21), new DateTime(2026, 12, 21), new DateTime(2026, 8, 15) })
        {
            double sr, ss;
            bool ok = SolarClock.SunTimes(d, 48.8566, 2.3522, out sr, out ss);
            Console.WriteLine(string.Format("  {0:dd/MM/yyyy}  lever {1}  coucher {2}",
                d, SolarClock.FormatHour(sr), SolarClock.FormatHour(ss)));
            Check(ok, "calcul solaire valide");
            Check(sr > 3 && sr < 10, "lever plausible");
            Check(ss > 15 && ss < 23, "coucher plausible");
        }

        Console.WriteLine();
        Console.WriteLine("=== Bornes de securite ===");
        Check(SafetyGuard.ClampBrightness(-50) == 5, "valeur negative ramenee a 5 %");
        Check(SafetyGuard.ClampBrightness(9999) == 150, "valeur enorme ramenee a 150 %");
        Check(SafetyGuard.ClampBrightness(double.NaN) == 100, "NaN ramene a 100 %");
        Check(GammaEngine.Plan(5, true, true).OverlayAlpha <= 250, "voile jamais opaque");
        Console.WriteLine("  OK");

        Console.WriteLine();
        Console.WriteLine(failures == 0
            ? ">>> TOUS LES TESTS PASSENT"
            : ">>> " + failures + " ECHEC(S)");
        Environment.Exit(failures == 0 ? 0 : 1);
    }
}
