using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Threading;

namespace OpusScreen
{
    /// <summary>
    /// Luminosite qui suit le contenu affiche : une page blanche fait baisser l'ecran,
    /// une video sombre le fait remonter. C'est le principe de Gammy, absent aussi bien
    /// de f.lux que de PangoBright.
    ///
    /// Deux details qui font que cela fonctionne sans osciller :
    ///
    ///   - La mesure est prise par BitBlt sur le bureau, donc AVANT que la LUT ne soit
    ///     appliquee par la carte graphique. Notre propre effet n'entre pas dans la
    ///     mesure, ce qui interdit toute boucle de retroaction.
    ///   - Le voile est retire de la capture (WDA_EXCLUDEFROMCAPTURE), sinon il
    ///     s'auto-mesurerait. Cet indicateur a un second merite : le voile disparait
    ///     aussi des captures d'ecran de l'utilisateur, ce que PangoBright ne fait pas.
    /// </summary>
    public class ContentAdaptive : IDisposable
    {
        [DllImport("user32.dll")] private static extern IntPtr GetDC(IntPtr hwnd);
        [DllImport("user32.dll")] private static extern int ReleaseDC(IntPtr hwnd, IntPtr hdc);
        [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleDC(IntPtr hdc);
        [DllImport("gdi32.dll")] private static extern IntPtr CreateCompatibleBitmap(IntPtr hdc, int w, int h);
        [DllImport("gdi32.dll")] private static extern IntPtr SelectObject(IntPtr hdc, IntPtr obj);
        [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr obj);
        [DllImport("gdi32.dll")] private static extern bool DeleteDC(IntPtr hdc);
        [DllImport("gdi32.dll")] private static extern bool StretchBlt(IntPtr dst, int xd, int yd, int wd, int hd,
                                                                      IntPtr src, int xs, int ys, int ws, int hs, int rop);
        [DllImport("gdi32.dll")] private static extern int SetStretchBltMode(IntPtr hdc, int mode);

        private const int SRCCOPY = 0x00CC0020;
        private const int HALFTONE = 4;

        // Resolution d'analyse : suffisante pour juger d'une ambiance, negligeable a calculer.
        private const int SampleW = 48;
        private const int SampleH = 27;

        private Thread _worker;
        private volatile bool _running;
        private readonly AutoResetEvent _wake = new AutoResetEvent(false);

        private double _smoothed = -1;

        /// <summary>Bornes entre lesquelles l'automatisme a le droit de se deplacer.</summary>
        public double MinBrightness = 40;
        public double MaxBrightness = 110;

        /// <summary>1 = tres lent et stable, 10 = tres reactif. Au-dela de 6 l'ecran respire.</summary>
        public double Reactivity = 3;

        /// <summary>Intervalle de mesure en millisecondes.</summary>
        public int IntervalMs = 1200;

        /// <summary>Appele avec la luminosite suggeree. Toujours emis hors du thread d'interface.</summary>
        public event Action<double> SuggestedBrightness;

        public double LastMeasuredLuminance { get; private set; }

        public void Start()
        {
            if (_worker != null) return;
            _running = true;
            _worker = new Thread(Loop);
            _worker.IsBackground = true;
            _worker.Name = "OpusScreen-Adaptive";
            _worker.Priority = ThreadPriority.BelowNormal;
            _worker.Start();
        }

        public void Stop()
        {
            _running = false;
            _smoothed = -1;
            _wake.Set();
            _worker = null;
        }

        public bool IsRunning { get { return _running; } }

        private void Loop()
        {
            while (_running)
            {
                try
                {
                    double lum = MeasureScreenLuminance();
                    if (lum >= 0)
                    {
                        LastMeasuredLuminance = lum;

                        double target = TargetFor(lum);

                        // Lissage exponentiel : la reactivite pilote la constante de temps.
                        if (_smoothed < 0) _smoothed = target;
                        double alpha = Math.Max(0.02, Math.Min(0.5, Reactivity / 20.0));
                        _smoothed += (target - _smoothed) * alpha;

                        Action<double> h = SuggestedBrightness;
                        if (h != null) h(_smoothed);
                    }
                }
                catch { /* une mesure ratee n'interrompt pas la boucle */ }

                _wake.WaitOne(Math.Max(200, IntervalMs));
            }
        }

        /// <summary>
        /// Ecran clair -> on baisse, ecran sombre -> on monte. La racine carree evite
        /// que les scenes tres sombres ne fassent bondir la luminosite d'un coup.
        /// </summary>
        private double TargetFor(double luminance)
        {
            double t = Math.Sqrt(Math.Max(0, Math.Min(1, luminance)));
            double b = MaxBrightness - (MaxBrightness - MinBrightness) * t;
            return SafetyGuard.ClampBrightness(b);
        }

        /// <summary>Luminance perceptuelle moyenne du bureau, entre 0 et 1. -1 si la mesure a echoue.</summary>
        private double MeasureScreenLuminance()
        {
            IntPtr screen = IntPtr.Zero, mem = IntPtr.Zero, bmp = IntPtr.Zero, old = IntPtr.Zero;
            try
            {
                screen = GetDC(IntPtr.Zero);
                if (screen == IntPtr.Zero) return -1;

                mem = CreateCompatibleDC(screen);
                bmp = CreateCompatibleBitmap(screen, SampleW, SampleH);
                if (mem == IntPtr.Zero || bmp == IntPtr.Zero) return -1;

                old = SelectObject(mem, bmp);
                SetStretchBltMode(mem, HALFTONE);

                int sw = Native_GetSystemMetrics(78);   // SM_CXVIRTUALSCREEN
                int sh = Native_GetSystemMetrics(79);   // SM_CYVIRTUALSCREEN
                int sx = Native_GetSystemMetrics(76);   // SM_XVIRTUALSCREEN
                int sy = Native_GetSystemMetrics(77);   // SM_YVIRTUALSCREEN
                if (sw <= 0 || sh <= 0) return -1;

                if (!StretchBlt(mem, 0, 0, SampleW, SampleH, screen, sx, sy, sw, sh, SRCCOPY))
                    return -1;

                using (Bitmap managed = Image.FromHbitmap(bmp))
                {
                    double sum = 0;
                    int count = 0;
                    for (int y = 0; y < managed.Height; y++)
                        for (int x = 0; x < managed.Width; x++)
                        {
                            Color c = managed.GetPixel(x, y);
                            sum += (0.2126 * c.R + 0.7152 * c.G + 0.0722 * c.B) / 255.0;
                            count++;
                        }
                    return count > 0 ? sum / count : -1;
                }
            }
            catch { return -1; }
            finally
            {
                if (old != IntPtr.Zero && mem != IntPtr.Zero) SelectObject(mem, old);
                if (bmp != IntPtr.Zero) DeleteObject(bmp);
                if (mem != IntPtr.Zero) DeleteDC(mem);
                if (screen != IntPtr.Zero) ReleaseDC(IntPtr.Zero, screen);
            }
        }

        [DllImport("user32.dll", EntryPoint = "GetSystemMetrics")]
        private static extern int Native_GetSystemMetrics(int index);

        public void Dispose()
        {
            Stop();
            _wake.Close();
        }
    }
}
