using System;
using System.Collections.Generic;

namespace LumaFlux
{
    /// <summary>
    /// Convertit une temperature de couleur (Kelvin) en multiplicateurs RGB.
    /// C'est la partie "f.lux" du moteur : approximation du rayonnement du corps noir,
    /// normalisee pour que 6500 K soit exactement neutre (aucune modification de l'image).
    /// </summary>
    public static class ColorTemp
    {
        public const int MinKelvin = 1200;   // bougie tres chaude, comme le "late" de f.lux
        public const int MaxKelvin = 6500;   // lumiere du jour = neutre

        // Valeurs brutes de la formule a 6500 K, servant de reference de normalisation.
        private const double Ref6500R = 255.0;
        private const double Ref6500G = 254.1097;
        private const double Ref6500B = 250.0522;

        /// <summary>
        /// Renvoie {r, g, b} dans [0..1]. A 6500 K le resultat est exactement {1, 1, 1}.
        /// </summary>
        public static double[] Multipliers(int kelvin)
        {
            if (kelvin < MinKelvin) kelvin = MinKelvin;
            if (kelvin > MaxKelvin) kelvin = MaxKelvin;

            double t = kelvin / 100.0;
            double r, g, b;

            // --- rouge ---
            if (t <= 66.0) r = 255.0;
            else r = 329.698727446 * Math.Pow(t - 60.0, -0.1332047592);

            // --- vert ---
            if (t <= 66.0) g = 99.4708025861 * Math.Log(t) - 161.1195681661;
            else g = 288.1221695283 * Math.Pow(t - 60.0, -0.0755148492);

            // --- bleu ---
            if (t >= 66.0) b = 255.0;
            else if (t <= 19.0) b = 0.0;
            else b = 138.5177312231 * Math.Log(t - 10.0) - 305.0447927307;

            double[] m = new double[3];
            m[0] = Clamp01(r / Ref6500R);
            m[1] = Clamp01(g / Ref6500G);
            m[2] = Clamp01(b / Ref6500B);
            return m;
        }

        private static double Clamp01(double v)
        {
            if (v < 0.0) return 0.0;
            if (v > 1.0) return 1.0;
            return v;
        }

        /// <summary>Libelle court pour l'interface, ex. "3400 K - chaud".</summary>
        public static string Describe(int kelvin)
        {
            string mood;
            if (kelvin >= 6000) mood = "lumiere du jour";
            else if (kelvin >= 5000) mood = "legerement chaud";
            else if (kelvin >= 4000) mood = "halogene";
            else if (kelvin >= 3000) mood = "chaud";
            else if (kelvin >= 2200) mood = "lampe a incandescence";
            else mood = "bougie";
            return string.Format("{0} K - {1}", kelvin, mood);
        }
    }

    /// <summary>
    /// Un preset jour / nuit / tard.
    /// Les sept premiers sont ceux de f.lux, releves dans son fichier media\preset.json.
    /// </summary>
    public class Preset
    {
        public string Name;
        public string Description;
        public int Day, Night, Late;

        public Preset(string name, string desc, int day, int night, int late)
        {
            Name = name; Description = desc; Day = day; Night = night; Late = late;
        }

        public static List<Preset> BuiltIn()
        {
            List<Preset> p = new List<Preset>();
            p.Add(new Preset("Couleurs recommandees", "Chaud au coucher du soleil, bougie avant de dormir", 6500, 3400, 1900));
            p.Add(new Preset("Reduire la fatigue oculaire", "Moins de fatigue, jour et nuit", 5900, 3600, 2500));
            p.Add(new Preset("f.lux classique", "Chaud au coucher du soleil, et toute la nuit", 6500, 3400, 3400));
            p.Add(new Preset("Travail tardif", "Lumineux apres le coucher du soleil, puis on ralentit", 6500, 6500, 2300));
            p.Add(new Preset("Loin de l'equateur", "Une pointe de coucher de soleil, bougie au coucher", 6500, 5500, 1900));
            p.Add(new Preset("Peinture rupestre", "Lumiere tres chaude en permanence", 2700, 2300, 1500));
            p.Add(new Preset("Fidelite des couleurs", "Ajustements plus faibles, meilleure precision colorimetrique", 6500, 5000, 3400));
            p.Add(new Preset("Aucun", "Pas de changement de temperature", 6500, 6500, 6500));
            return p;
        }
    }
}
