using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

namespace OpusScreen
{
    /// <summary>
    /// Chef d'orchestre. Traduit une consigne en actions coordonnees sur quatre etages,
    /// ecran par ecran :
    ///
    ///     retroeclairage materiel -> LUT gamma -> matrice de couleur -> voile
    ///
    /// Les modules en dessous ne se connaissent pas entre eux ; c'est ici, et seulement
    /// ici, qu'ils sont assembles. L'interface, elle, ne parle qu'a cette classe.
    ///
    /// Trois des quatre etages sont reglables ecran par ecran. Le quatrieme, la
    /// matrice de couleur, ne l'est pas : l'API Magnification n'expose qu'un effet
    /// pour tout le bureau. Cette contrainte n'est pas masquee - un ecran de
    /// reference est designe explicitement, et l'interface le dit.
    /// </summary>
    public class DisplayController : IDisposable
    {
        private readonly Settings _settings;
        private readonly OverlaySet _overlays = new OverlaySet();
        private List<MonitorInfo> _monitors = new List<MonitorInfo>();

        // Transition douce : on garde ce qui est affiche et ce que l'on vise.
        private readonly Dictionary<string, Profile> _displayed = new Dictionary<string, Profile>();
        private readonly Timer _fade = new Timer();
        private DateTime _fadeStart;
        private readonly Dictionary<string, Profile> _fadeFrom = new Dictionary<string, Profile>();
        private readonly Dictionary<string, Profile> _fadeTo = new Dictionary<string, Profile>();

        // Diagnostics accumules sur une passe complete, jamais sur le dernier ecran vu.
        private bool _passClip, _passClamped;

        public bool GammaClamped { get; private set; }
        public bool Clipping { get; private set; }
        public bool ColorMatrixFailed { get; private set; }
        public string HardwareStatus = "non teste";

        /// <summary>Vrai quand tout effet est suspendu (pause, plein ecran, regle d'application).</summary>
        public bool Suspended { get; private set; }
        public string SuspendReason = "";

        /// <summary>
        /// Vrai quand le seul voile est retire, les autres etages restant en place.
        /// Suspendre tout etait la seule reponse possible a un jeu ou une video ; c'en
        /// est une bien trop large, puisque le voile est le seul etage qui les gene.
        /// </summary>
        public bool OverlayHeld { get; private set; }
        public string OverlayHoldReason = "";

        public DisplayController(Settings settings)
        {
            _settings = settings;
            RefreshMonitors();

            _fade.Interval = 33;              // ~30 images par seconde
            _fade.Tick += OnFadeTick;
        }

        public List<MonitorInfo> Monitors { get { return _monitors; } }

        public void RefreshMonitors()
        {
            _monitors = MonitorEnum.All();
            _overlays.PruneMissing(_monitors);

            foreach (MonitorInfo m in _monitors)
            {
                MonitorSettings ms = _settings.For(m);
                ms.FriendlyName = m.FriendlyName;   // le nom peut changer au rebranchement
            }

            // Un ecran debranche laissait derriere lui son dernier etat affiche, ce qui
            // suffisait a faire croire qu'un effet restait actif alors que plus rien
            // n'etait pose.
            List<string> alive = new List<string>();
            foreach (MonitorInfo m in _monitors) alive.Add(m.StableId);
            List<string> stale = new List<string>();
            foreach (string id in _displayed.Keys) if (!alive.Contains(id)) stale.Add(id);
            foreach (string id in stale) _displayed.Remove(id);
        }

        // ------------------------------------------------------------------ suspension

        public void Suspend(string reason)
        {
            if (Suspended && SuspendReason == reason) return;
            Suspended = true;
            SuspendReason = reason;
            ApplyNow(true);
        }

        public void Resume()
        {
            if (!Suspended) return;
            Suspended = false;
            SuspendReason = "";
            Apply();
        }

        /// <summary>Retire le voile sans toucher aux autres etages.</summary>
        public void HoldOverlay(string reason)
        {
            if (OverlayHeld && OverlayHoldReason == reason) return;
            OverlayHeld = true;
            OverlayHoldReason = reason;
            ApplyNow(false);
        }

        public void ReleaseOverlay()
        {
            if (!OverlayHeld) return;
            OverlayHeld = false;
            OverlayHoldReason = "";
            Apply();
        }

        // ------------------------------------------------------------------ application

        /// <summary>Applique l'etat courant, avec fondu si l'option est active.</summary>
        public void Apply()
        {
            if (!_settings.SmoothTransitions || _settings.TransitionSpeedMs < 60)
            {
                ApplyNow(false);
                return;
            }

            _fadeFrom.Clear();
            _fadeTo.Clear();
            bool anyChange = false;

            foreach (MonitorInfo m in _monitors)
            {
                Profile target = ResolveTarget(m);
                Profile from;
                if (!_displayed.TryGetValue(m.StableId, out from)) from = target.Clone();

                _fadeFrom[m.StableId] = from.Clone();
                _fadeTo[m.StableId] = target.Clone();
                if (!Same(from, target)) anyChange = true;
            }

            if (!anyChange) { ApplyNow(false); return; }

            _fadeStart = DateTime.Now;
            _fade.Start();
        }

        private void OnFadeTick(object sender, EventArgs e)
        {
            double elapsed = (DateTime.Now - _fadeStart).TotalMilliseconds;
            double t = elapsed / Math.Max(60, _settings.TransitionSpeedMs);
            if (t >= 1.0) { t = 1.0; _fade.Stop(); }

            // Adoucissement en cosinus : demarrage et arrivee sans a-coup.
            double eased = 0.5 - 0.5 * Math.Cos(Math.PI * t);

            BeginPass();
            foreach (MonitorInfo m in _monitors)
            {
                Profile a, b;
                if (!_fadeFrom.TryGetValue(m.StableId, out a)) continue;
                if (!_fadeTo.TryGetValue(m.StableId, out b)) continue;
                ApplyToMonitor(m, Lerp(a, b, eased));
            }
            EndPass();

            if (t >= 1.0) FinishApply();
        }

        /// <summary>Applique immediatement, sans fondu.</summary>
        public void ApplyNow(bool fromSuspend)
        {
            _fade.Stop();
            BeginPass();
            foreach (MonitorInfo m in _monitors)
                ApplyToMonitor(m, ResolveTarget(m));
            EndPass();
            FinishApply();
        }

        /// <summary>
        /// Les indicateurs d'ecretage et de bridage decrivent une CONFIGURATION, pas un
        /// ecran : ils sont donc remis a zero avant chaque passe puis cumules sur tous
        /// les ecrans. Sans cela, le dernier ecran parcouru effacait le diagnostic du
        /// premier - et sur deux ecrans, l'avertissement disparaissait une fois sur deux.
        /// </summary>
        private void BeginPass()
        {
            _passClip = false;
            _passClamped = false;
        }

        private void EndPass()
        {
            Clipping = _passClip;
            GammaClamped = _passClamped;
        }

        private void FinishApply()
        {
            // Etage matrice de couleur : global au bureau, pas par ecran.
            Profile reference = MatrixProfile();
            if (_settings.UseColorMatrix)
            {
                bool ok = ColorMatrixEffect.Apply(reference.Saturation, reference.Filter,
                                                  reference.VisionSeverity, reference.FilterStrength,
                                                  reference.Mode);
                bool wanted = !ColorMatrixEffect.IsNeutralRequest(
                    reference.Saturation, reference.Filter, reference.VisionSeverity,
                    reference.FilterStrength, reference.Mode);
                ColorMatrixFailed = !ok && wanted;
            }
            else
            {
                ColorMatrixEffect.Reset();
                ColorMatrixFailed = false;
            }

            bool anythingActive = false;
            foreach (Profile p in _displayed.Values)
                if (!p.IsNeutral()) { anythingActive = true; break; }

            foreach (MonitorInfo m in _monitors)
                if (_settings.For(m).Blackout) anythingActive = true;

            if (anythingActive) SafetyGuard.MarkDirty();
            else SafetyGuard.ClearDirtyFlag();
        }

        /// <summary>Ce que cet ecran doit afficher, tout compris.</summary>
        private Profile ResolveTarget(MonitorInfo m)
        {
            MonitorSettings ms = _settings.For(m);

            if (Suspended || !ms.Enabled) return new Profile();   // profil neutre
            if (ms.Blackout)
            {
                Profile black = new Profile();
                black.Brightness = GammaEngine.MinBrightness;
                black.Tint = Color.Black;
                return black;
            }
            return _settings.EffectiveFor(m);
        }

        /// <summary>
        /// L'ecran dont les reglages de couleur pilotent la matrice plein ecran.
        ///
        /// Par defaut l'ecran principal, mais le choix est explicite : sur un poste ou
        /// l'ecran principal est un ecran d'appoint, la saturation et les filtres
        /// etaient regles depuis un ecran que l'utilisateur ne regardait pas.
        /// </summary>
        public MonitorInfo MatrixSourceMonitor()
        {
            if (!string.IsNullOrEmpty(_settings.MatrixSourceId))
                foreach (MonitorInfo m in _monitors)
                    if (m.StableId == _settings.MatrixSourceId) return m;

            foreach (MonitorInfo m in _monitors)
                if (m.IsPrimary) return m;

            return _monitors.Count > 0 ? _monitors[0] : null;
        }

        private Profile MatrixProfile()
        {
            MonitorInfo m = MatrixSourceMonitor();
            return m != null ? ResolveTarget(m) : new Profile();
        }

        private void ApplyToMonitor(MonitorInfo m, Profile p)
        {
            MonitorSettings ms = _settings.For(m);

            BrightnessPlan plan = GammaEngine.Plan(
                p.Brightness,
                _settings.UseOverlay && !OverlayHeld,
                _settings.UseHardwareBacklight && !Suspended);

            _passClip |= plan.Clips;

            // Consigne NOMINATIVE. La version precedente envoyait un niveau global
            // depuis une boucle par ecran : sur deux ecrans, le dernier traite imposait
            // sa luminosite materielle aux autres.
            if (plan.HardwareTarget >= 0)
                HardwareBacklight.RequestLevel(m, plan.HardwareTarget);

            Native.RampTable ramp = GammaEngine.BuildRamp(plan, p);
            GammaApplyResult r = GammaEngine.Apply(m, ramp);
            if (r.Success && r.Clamped) _passClamped = true;

            // Le mode BlackOut pousse le voile bien au-dela du plan normal.
            double transmission = ms.Blackout && !Suspended && !OverlayHeld ? 0.02 : plan.OverlayTransmission;
            _overlays.Update(m, transmission, p.Tint);

            _displayed[m.StableId] = p.Clone();
        }

        // ------------------------------------------------------------------ interpolation

        private static Profile Lerp(Profile a, Profile b, double t)
        {
            Profile p = new Profile();
            p.Name = b.Name;
            p.Brightness = a.Brightness + (b.Brightness - a.Brightness) * t;
            p.Kelvin = (int)Math.Round(a.Kelvin + (b.Kelvin - a.Kelvin) * t);
            p.Contrast = a.Contrast + (b.Contrast - a.Contrast) * t;
            p.GammaCurve = a.GammaCurve + (b.GammaCurve - a.GammaCurve) * t;
            p.RedGain = a.RedGain + (b.RedGain - a.RedGain) * t;
            p.GreenGain = a.GreenGain + (b.GreenGain - a.GreenGain) * t;
            p.BlueGain = a.BlueGain + (b.BlueGain - a.BlueGain) * t;
            p.Saturation = a.Saturation + (b.Saturation - a.Saturation) * t;
            p.VisionSeverity = a.VisionSeverity + (b.VisionSeverity - a.VisionSeverity) * t;
            p.FilterStrength = a.FilterStrength + (b.FilterStrength - a.FilterStrength) * t;
            // Le filtre ne s'interpole pas : il bascule a mi-parcours.
            p.Filter = t < 0.5 ? a.Filter : b.Filter;
            p.Mode = t < 0.5 ? a.Mode : b.Mode;
            p.Tint = t < 0.5 ? a.Tint : b.Tint;
            return p;
        }

        private static bool Same(Profile a, Profile b)
        {
            return Math.Abs(a.Brightness - b.Brightness) < 0.01
                && a.Kelvin == b.Kelvin
                && Math.Abs(a.Contrast - b.Contrast) < 0.01
                && Math.Abs(a.GammaCurve - b.GammaCurve) < 0.01
                && Math.Abs(a.RedGain - b.RedGain) < 0.01
                && Math.Abs(a.GreenGain - b.GreenGain) < 0.01
                && Math.Abs(a.BlueGain - b.BlueGain) < 0.01
                && Math.Abs(a.Saturation - b.Saturation) < 0.01
                && Math.Abs(a.VisionSeverity - b.VisionSeverity) < 0.01
                && Math.Abs(a.FilterStrength - b.FilterStrength) < 0.01
                && a.Filter == b.Filter && a.Mode == b.Mode && a.Tint == b.Tint;
        }

        // ------------------------------------------------------------------ restauration

        public void RestoreAll()
        {
            _fade.Stop();
            _overlays.HideAll();
            ColorMatrixEffect.Reset();
            foreach (MonitorInfo m in _monitors)
            {
                try { GammaEngine.ResetToIdentity(m); } catch { }
            }
            _displayed.Clear();
            Clipping = false;
            GammaClamped = false;
            SafetyGuard.ClearDirtyFlag();
        }

        /// <summary>Reapplique si un autre programme a ecrase notre LUT.</summary>
        public void ReapplyIfNeeded()
        {
            if (_fade.Enabled) return;
            BeginPass();
            bool touched = false;
            foreach (MonitorInfo m in _monitors)
            {
                Profile p = ResolveTarget(m);
                if (p.IsNeutral() && !_settings.For(m).Blackout) continue;
                ApplyToMonitor(m, p);
                touched = true;
            }
            if (touched) EndPass();
        }

        // ------------------------------------------------------------------ diagnostics

        /// <summary>Explique en une ligne ce que fait le reglage courant.</summary>
        public string DescribeCurrentPlan()
        {
            if (Suspended) return "suspendu - " + SuspendReason;

            Profile p = MatrixProfile();
            BrightnessPlan plan = GammaEngine.Plan(p.Brightness,
                _settings.UseOverlay && !OverlayHeld, _settings.UseHardwareBacklight);

            List<string> parts = new List<string>();
            if (plan.HardwareTarget >= 0) parts.Add("retroeclairage au maximum");
            if (Math.Abs(plan.GammaExponent - 1.0) > 0.001)
                parts.Add(string.Format("courbe gamma {0:0.00}", plan.GammaExponent));
            if (Math.Abs(plan.LinearGain - 1.0) > 0.001)
                parts.Add(string.Format("gain {0:0.00}x", plan.LinearGain));
            if (plan.OverlayTransmission < 1.0)
                parts.Add(string.Format("voile {0} %", (int)Math.Round((1 - plan.OverlayTransmission) * 100)));
            if (!ColorMatrixEffect.IsNeutralRequest(p.Saturation, p.Filter, p.VisionSeverity, p.FilterStrength, p.Mode))
                parts.Add("matrice de couleur");

            if (OverlayHeld) parts.Add("voile retire - " + OverlayHoldReason);

            if (parts.Count == 0) return "ecran normal, aucune modification";
            return string.Join(" + ", parts.ToArray());
        }

        public bool AnyGammaSupport()
        {
            foreach (MonitorInfo m in _monitors)
                if (GammaEngine.SupportsGamma(m)) return true;
            return false;
        }

        public void Dispose()
        {
            try { _fade.Stop(); _fade.Dispose(); } catch { }
            try { RestoreAll(); } catch { }
            try { _overlays.Dispose(); } catch { }
            try { ScreenMagnifier.Stop(); } catch { }
            try { ColorMatrixEffect.Shutdown(); } catch { }
        }
    }
}
