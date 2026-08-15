using System;
using OpusScreen;

class MatrixTest
{
    static int fails = 0;
    static void Check(bool ok, string what) { if (!ok) { Console.WriteLine("  ECHEC : " + what); fails++; } }

    // Applique une matrice 5x5 a un pixel [r,g,b,1,1] selon la convention vecteur-ligne.
    static double[] Apply(float[] m, double r, double g, double b)
    {
        double[] inp = { r, g, b, 1, 1 };
        double[] outp = new double[5];
        for (int j = 0; j < 5; j++) { double s = 0; for (int i = 0; i < 5; i++) s += inp[i] * m[i * 5 + j]; outp[j] = s; }
        return outp;
    }

    static float[] Sat(double s)
    {
        var mi = typeof(ColorMatrixEffect).GetMethod("SaturationMatrix",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);
        return (float[])mi.Invoke(null, new object[] { s });
    }
    static float[] Filt(ColorFilter f)
    {
        var mi = typeof(ColorMatrixEffect).GetMethod("FilterMatrix",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);
        return (float[])mi.Invoke(null, new object[] { f });
    }

    static void Main()
    {
        Console.WriteLine("=== Identite ===");
        double[] id = Apply(ColorMatrixEffect.Identity(), 0.3, 0.6, 0.9);
        Console.WriteLine(string.Format("  (0.3,0.6,0.9) -> ({0:0.000},{1:0.000},{2:0.000})", id[0], id[1], id[2]));
        Check(Math.Abs(id[0]-0.3)<1e-6 && Math.Abs(id[1]-0.6)<1e-6 && Math.Abs(id[2]-0.9)<1e-6, "identite neutre");

        Console.WriteLine();
        Console.WriteLine("=== Saturation 0 : les trois canaux doivent converger ===");
        double[] gray = Apply(Sat(0), 0.2, 0.7, 0.4);
        Console.WriteLine(string.Format("  (0.2,0.7,0.4) -> ({0:0.000},{1:0.000},{2:0.000})", gray[0], gray[1], gray[2]));
        Check(Math.Abs(gray[0]-gray[1])<1e-5 && Math.Abs(gray[1]-gray[2])<1e-5, "saturation 0 = gris");
        double expected = 0.2126*0.2 + 0.7152*0.7 + 0.0722*0.4;
        Check(Math.Abs(gray[0]-expected)<1e-5, "luminance Rec.709 exacte (attendu " + expected.ToString("0.0000") + ")");

        Console.WriteLine();
        Console.WriteLine("=== Saturation 1 : aucun changement ===");
        double[] s1 = Apply(Sat(1), 0.2, 0.7, 0.4);
        Check(Math.Abs(s1[0]-0.2)<1e-5 && Math.Abs(s1[1]-0.7)<1e-5 && Math.Abs(s1[2]-0.4)<1e-5, "saturation 1 = neutre");
        Console.WriteLine("  OK");

        Console.WriteLine();
        Console.WriteLine("=== Inversion ===");
        double[] inv = Apply(Filt(ColorFilter.Invert), 0.25, 0.5, 0.75);
        Console.WriteLine(string.Format("  (0.25,0.5,0.75) -> ({0:0.000},{1:0.000},{2:0.000})", inv[0], inv[1], inv[2]));
        Check(Math.Abs(inv[0]-0.75)<1e-5 && Math.Abs(inv[1]-0.5)<1e-5 && Math.Abs(inv[2]-0.25)<1e-5, "inversion = 1 - entree");

        Console.WriteLine();
        Console.WriteLine("=== Sepia : le blanc reste clair, la teinte vire au chaud ===");
        double[] sep = Apply(Filt(ColorFilter.Sepia), 1, 1, 1);
        Console.WriteLine(string.Format("  blanc -> ({0:0.000},{1:0.000},{2:0.000})", sep[0], sep[1], sep[2]));
        Check(sep[0] > sep[1] && sep[1] > sep[2], "R > V > B (chaud)");

        Console.WriteLine();
        Console.WriteLine("=== Filtres daltonisme : gris preserve, couleurs redistribuees ===");
        foreach (ColorFilter f in new[] { ColorFilter.Protanopia, ColorFilter.Deuteranopia, ColorFilter.Tritanopia })
        {
            float[] m = Filt(f);
            double[] g = Apply(m, 0.5, 0.5, 0.5);
            double[] red = Apply(m, 1, 0, 0);
            double[] grn = Apply(m, 0, 1, 0);
            Console.WriteLine(string.Format("  {0,-14} gris->({1:0.00},{2:0.00},{3:0.00})  rouge->({4:0.00},{5:0.00},{6:0.00})  vert->({7:0.00},{8:0.00},{9:0.00})",
                f, g[0],g[1],g[2], red[0],red[1],red[2], grn[0],grn[1],grn[2]));
            Check(Math.Abs(g[0]-0.5)<0.06 && Math.Abs(g[1]-0.5)<0.06 && Math.Abs(g[2]-0.5)<0.06, f + " : le gris ne doit pas deriver");
            double sepBefore = Math.Abs(1-0) + Math.Abs(0-1);
            double sepAfter = Math.Abs(red[0]-grn[0]) + Math.Abs(red[1]-grn[1]) + Math.Abs(red[2]-grn[2]);
            Check(sepAfter > 0.5, f + " : rouge et vert doivent rester distincts");
        }

        Console.WriteLine();
        Console.WriteLine("=== LUT etendue : contraste, courbe, balance ===");
        BrightnessPlan plan = GammaEngine.Plan(100, true, true);
        Profile p = new Profile();
        p.Contrast = 130; p.GammaCurve = 120; p.RedGain = 90; p.BlueGain = 110;
        Native.RampTable r2 = GammaEngine.BuildRamp(plan, p);
        for (int i = 1; i < 256; i++)
        {
            Check(r2.Red[i] >= r2.Red[i-1], "rampe rouge croissante");
            Check(r2.Green[i] >= r2.Green[i-1], "rampe verte croissante");
            Check(r2.Blue[i] >= r2.Blue[i-1], "rampe bleue croissante");
        }
        Console.WriteLine(string.Format("  contraste 130 : entree 64 -> {0}, entree 192 -> {1} (etalement attendu)", r2.Green[64], r2.Green[192]));
        Check(r2.Blue[200] > r2.Red[200], "BlueGain 110 > RedGain 90");
        Console.WriteLine("  OK");

        Console.WriteLine();
        Console.WriteLine(fails == 0 ? ">>> TOUS LES TESTS PASSENT" : ">>> " + fails + " ECHEC(S)");
        Environment.Exit(fails == 0 ? 0 : 1);
    }
}
