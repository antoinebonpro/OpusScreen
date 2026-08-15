using System;

namespace OpusScreen
{
    /// <summary>
    /// Repartition d'une consigne de luminosite entre les trois etages disponibles.
    /// C'est ici qu'est encode le choix de conception "hybride intelligent".
    /// </summary>
    public struct BrightnessPlan
    {
        public double GammaExponent;        // g : out = in^(1/g). g > 1 eclaircit sans ecreter.
        public double LinearGain;           // multiplicateur final. > 1 ecrete les hautes lumieres.
        public double OverlayTransmission;  // 1.0 = aucun voile ; 0.15 = voile laissant passer 15 %
        public int HardwareTarget;          // retroeclairage physique vise, ou -1 pour ne pas y toucher
        public bool Clips;                  // vrai si des hautes lumieres seront ecretees

        public byte OverlayAlpha
        {
            get
            {
                double a = (1.0 - OverlayTransmission) * 255.0;
                if (a < 0) a = 0;
                if (a > 250) a = 250;   // garde-fou : jamais un voile totalement opaque
                return (byte)Math.Round(a);
            }
        }
    }

    public class GammaApplyResult
    {
        public bool Success;              // la rampe a ete acceptee par le pilote
        public bool Clamped;              // Windows l'a rabotee vers la lineaire
        public double EffectiveScale = 1; // 1.0 = applique telle quelle ; < 1 = repli
    }

    /// <summary>
    /// Construit et applique la LUT du GPU. C'est la technique de f.lux
    /// (SetDeviceGammaRamp), etendue au-dela de 100 % de luminosite.
    /// </summary>
    public static class GammaEngine
    {
        public const double MinBrightness = 5.0;
        public const double MaxBrightness = 150.0;

        /// <summary>
        /// En dessous de ce seuil, la gamma seule devient sale (bandes de couleur,
        /// perte de nuances) : le voile facon PangoBright prend alors le relais.
        /// </summary>
        private const double GammaFloor = 35.0;

        // ------------------------------------------------------------------ le plan

        /// <summary>
        /// Traduit une consigne 5-150 % en reglages concrets pour les trois etages.
        ///
        ///   B <= 35 %  : gamma au plancher + voile qui absorbe le reste
        ///   35 - 100 % : gain lineaire descendant, aucun voile
        ///   100 - 135 %: courbe gamma pure -> AUCUN ecretage, aucune perte
        ///   135 - 150 %: on ajoute un peu de gain lineaire, quelques blancs ecretes
        ///   > 100 %    : le retroeclairage physique est pousse au maximum
        /// </summary>
        public static BrightnessPlan Plan(double brightness, bool allowOverlay, bool allowHardware)
        {
            if (brightness < MinBrightness) brightness = MinBrightness;
            if (brightness > MaxBrightness) brightness = MaxBrightness;

            BrightnessPlan p = new BrightnessPlan();
            p.GammaExponent = 1.0;
            p.LinearGain = 1.0;
            p.OverlayTransmission = 1.0;
            p.HardwareTarget = -1;
            p.Clips = false;

            double ratio = brightness / 100.0;

            if (brightness > 100.0)
            {
                // --- etage 1 : de vrais photons en plus, quand le materiel le permet
                if (allowHardware) p.HardwareTarget = 100;

                // --- etage 2 : courbe gamma. 0 reste 0, 1 reste 1 : zero perte.
                p.GammaExponent = 1.0 + (ratio - 1.0) * 1.6;

                // --- etage 3 : gain lineaire, uniquement dans le dernier tiers
                double linearStart = 1.35;
                if (ratio > linearStart)
                {
                    p.LinearGain = 1.0 + (ratio - linearStart) * 0.8;
                    p.Clips = true;
                }
            }
            else if (brightness >= GammaFloor)
            {
                // Assombrissement propre par la LUT : invisible aux captures d'ecran,
                // fonctionne dans les jeux plein ecran.
                p.LinearGain = ratio;
            }
            else
            {
                // Sous le plancher : la LUT reste a 35 %, le voile absorbe le reste.
                p.LinearGain = GammaFloor / 100.0;
                double remaining = brightness / GammaFloor;   // 0.14 a 1.0
                if (allowOverlay)
                {
                    p.OverlayTransmission = remaining;
                }
                else
                {
                    // Sans voile autorise, on descend au maximum de ce que la LUT permet.
                    p.LinearGain = ratio;
                }
            }

            return p;
        }

        // ------------------------------------------------------------------ la rampe

        /// <summary>
        /// Fabrique la LUT : luminosite et temperature fusionnees en une seule passe.
        ///     ramp[c][i] = ( (i/255)^(1/g) * gain * tempMult[c] ) * 65535
        /// </summary>
        public static Native.RampTable BuildRamp(BrightnessPlan plan, int kelvin)
        {
            Profile p = new Profile();
            p.Kelvin = kelvin;
            return BuildRamp(plan, p);
        }

        /// <summary>
        /// Version complete : ajoute a la passe precedente le contraste, la courbe gamma
        /// choisie par l'utilisateur et la balance manuelle des trois canaux.
        ///
        /// Ordre des operations, du plus structurel au plus cosmetique :
        ///   1. courbe      : forme de la reponse (plan de luminosite x reglage utilisateur)
        ///   2. contraste   : etalement autour du gris moyen
        ///   3. gain        : niveau general
        ///   4. couleur     : temperature puis balance manuelle des canaux
        /// </summary>
        public static Native.RampTable BuildRamp(BrightnessPlan plan, Profile profile)
        {
            double[] temp = ColorTemp.Multipliers(profile.Kelvin);
            Native.RampTable ramp = Native.RampTable.Allocate();

            // La courbe du plan (boost) et celle choisie par l'utilisateur se composent.
            double gamma = plan.GammaExponent * (profile.GammaCurve / 100.0);
            if (gamma < 0.2) gamma = 0.2;
            double invGamma = 1.0 / gamma;

            double contrast = profile.Contrast / 100.0;

            double rMul = temp[0] * (profile.RedGain / 100.0);
            double gMul = temp[1] * (profile.GreenGain / 100.0);
            double bMul = temp[2] * (profile.BlueGain / 100.0);

            for (int i = 0; i < 256; i++)
            {
                double v = i / 255.0;

                if (Math.Abs(gamma - 1.0) > 1e-9) v = Math.Pow(v, invGamma);

                // Contraste : etirement autour de 0.5, le gris moyen ne bouge pas.
                if (Math.Abs(contrast - 1.0) > 1e-9)
                {
                    v = 0.5 + (v - 0.5) * contrast;
                    if (v < 0) v = 0; else if (v > 1) v = 1;
                }

                v *= plan.LinearGain;

                ramp.Red[i] = ToRampValue(v * rMul);
                ramp.Green[i] = ToRampValue(v * gMul);
                ramp.Blue[i] = ToRampValue(v * bMul);
            }
            return ramp;
        }

        private static ushort ToRampValue(double v)
        {
            double scaled = v * 65535.0;
            if (scaled < 0) scaled = 0;
            if (scaled > 65535) scaled = 65535;
            return (ushort)Math.Round(scaled);
        }

        /// <summary>Melange une rampe avec l'identite. t=0 -> identite, t=1 -> rampe complete.</summary>
        public static Native.RampTable Blend(Native.RampTable ramp, double t)
        {
            if (t >= 1.0) return ramp;
            if (t < 0) t = 0;
            Native.RampTable id = Native.RampTable.Identity();
            Native.RampTable outp = Native.RampTable.Allocate();
            for (int i = 0; i < 256; i++)
            {
                outp.Red[i] = (ushort)(id.Red[i] + (ramp.Red[i] - id.Red[i]) * t);
                outp.Green[i] = (ushort)(id.Green[i] + (ramp.Green[i] - id.Green[i]) * t);
                outp.Blue[i] = (ushort)(id.Blue[i] + (ramp.Blue[i] - id.Blue[i]) * t);
            }
            return outp;
        }

        // ------------------------------------------------------------------ acces au pilote

        private static IntPtr OpenDC(MonitorInfo m)
        {
            return Native.CreateDC("DISPLAY", m != null ? m.DeviceName : null, null, IntPtr.Zero);
        }

        public static bool SupportsGamma(MonitorInfo m)
        {
            IntPtr dc = OpenDC(m);
            if (dc == IntPtr.Zero) return false;
            try
            {
                int caps = Native.GetDeviceCaps(dc, Native.COLORMGMTCAPS);
                return (caps & Native.CM_GAMMA_RAMP) != 0;
            }
            finally { Native.DeleteDC(dc); }
        }

        /// <summary>Lit la rampe actuellement en place, pour pouvoir la remettre plus tard.</summary>
        public static Native.RampTable Capture(MonitorInfo m)
        {
            IntPtr dc = OpenDC(m);
            if (dc == IntPtr.Zero) return Native.RampTable.Identity();
            try
            {
                Native.RampTable r = Native.RampTable.Allocate();
                if (Native.GetDeviceGammaRamp(dc, ref r)) return r;
                return Native.RampTable.Identity();
            }
            catch { return Native.RampTable.Identity(); }
            finally { Native.DeleteDC(dc); }
        }

        /// <summary>
        /// Applique la rampe. Si Windows la refuse (bridage GdiIcmGammaRange), on
        /// redescend progressivement jusqu'a une version acceptee plutot que d'echouer
        /// en silence : l'utilisateur voit un effet reduit, jamais un effet nul inexplique.
        /// </summary>
        public static GammaApplyResult Apply(MonitorInfo m, Native.RampTable ramp)
        {
            GammaApplyResult res = new GammaApplyResult();
            IntPtr dc = OpenDC(m);
            if (dc == IntPtr.Zero) return res;

            try
            {
                Native.RampTable attempt = ramp;
                double[] steps = new double[] { 1.0, 0.85, 0.7, 0.55, 0.4, 0.25, 0.1 };

                foreach (double t in steps)
                {
                    attempt = t >= 1.0 ? ramp : Blend(ramp, t);
                    if (Native.SetDeviceGammaRamp(dc, ref attempt))
                    {
                        res.Success = true;
                        res.EffectiveScale = t;
                        res.Clamped = DiffersFromWritten(dc, attempt) || t < 1.0;
                        return res;
                    }
                }
                return res;
            }
            catch { return res; }
            finally { Native.DeleteDC(dc); }
        }

        /// <summary>
        /// Relit la rampe et la compare a celle qu'on vient d'ecrire. Un ecart notable
        /// signifie que Windows l'a rabotee vers la lineaire.
        /// </summary>
        private static bool DiffersFromWritten(IntPtr dc, Native.RampTable written)
        {
            try
            {
                Native.RampTable back = Native.RampTable.Allocate();
                if (!Native.GetDeviceGammaRamp(dc, ref back)) return false;

                int maxDiff = 0;
                for (int i = 0; i < 256; i++)
                {
                    maxDiff = Math.Max(maxDiff, Math.Abs(back.Red[i] - written.Red[i]));
                    maxDiff = Math.Max(maxDiff, Math.Abs(back.Green[i] - written.Green[i]));
                    maxDiff = Math.Max(maxDiff, Math.Abs(back.Blue[i] - written.Blue[i]));
                }
                return maxDiff > 2048;   // ~3 % de l'echelle : au-dela ce n'est plus un arrondi
            }
            catch { return false; }
        }

        /// <summary>Remet la rampe identite : l'ecran redevient strictement normal.</summary>
        public static bool ResetToIdentity(MonitorInfo m)
        {
            IntPtr dc = OpenDC(m);
            if (dc == IntPtr.Zero) return false;
            try
            {
                Native.RampTable id = Native.RampTable.Identity();
                return Native.SetDeviceGammaRamp(dc, ref id);
            }
            catch { return false; }
            finally { Native.DeleteDC(dc); }
        }
    }
}
