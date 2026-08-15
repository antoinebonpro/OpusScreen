using System;
using LumaFlux;
class DpstTest
{
    static void Main()
    {
        Console.WriteLine("=== Cartes Intel detectees ===");
        foreach (IntelDpst.Adapter a in IntelDpst.FindIntelAdapters())
            Console.WriteLine(string.Format("  {0}\n    FeatureTestControl = 0x{1:X4}   DPST {2}",
                a.Description, a.FeatureTestControl, a.DpstActive ? "ACTIF" : "desactive"));
        Console.WriteLine();
        Console.WriteLine("LACE actif      : " + IntelDpst.IsLaceActive());
        Console.WriteLine("DPST actif      : " + IntelDpst.IsAnyDpstActive());
        Console.WriteLine("Resume          : " + IntelDpst.Describe());
        Console.WriteLine();
        Console.WriteLine("=== Verification du calcul de bit (sans rien ecrire) ===");
        foreach (IntelDpst.Adapter a in IntelDpst.FindIntelAdapters())
            Console.WriteLine(string.Format("  0x{0:X4} -> 0x{1:X4} apres desactivation",
                a.FeatureTestControl, a.FeatureTestControl | 0x20));
    }
}
