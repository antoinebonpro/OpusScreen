using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

/// <summary>
/// Generateur de l'icone de l'application.
///
/// L'icone est dessinee plutot que livree en binaire : elle se relit, se corrige et
/// se regenere avec le reste du projet, et chaque taille est tracee separement au
/// lieu d'etre reduite depuis une grande image - c'est la seule facon d'obtenir un
/// 16x16 net dans la barre des taches.
/// </summary>
internal static class MakeIcon
{
    // Les tailles que Windows va chercher : barre des taches, explorateur, alt-tab,
    // grandes icones et vignette 256 du volet d'apercu.
    private static readonly int[] Sizes = { 16, 20, 24, 32, 40, 48, 64, 128, 256 };

    /// <summary>Logo fourni par le projet. Null si le fichier manque : le trace de secours prend alors le relais.</summary>
    private static Bitmap _logo;

    /// <summary>Zone reellement occupee par le dessin, marges transparentes exclues.</summary>
    private static Rectangle _logoBox;

    private static int Main(string[] args)
    {
        string path = Path.GetFullPath(args.Length > 0 ? args[0] : "OpusScreen.ico");
        string logoPath = args.Length > 1
            ? Path.GetFullPath(args[1])
            : Path.Combine(Path.GetDirectoryName(path) ?? ".", "logo.png");

        try
        {
            string dir = Path.GetDirectoryName(path);
            if (dir.Length > 0) Directory.CreateDirectory(dir);

            LoadLogo(logoPath);

            List<Bitmap> images = new List<Bitmap>();
            foreach (int s in Sizes) images.Add(Draw(s));

            using (FileStream fs = new FileStream(path, FileMode.Create, FileAccess.Write))
                Write(fs, images);

            foreach (Bitmap b in images) b.Dispose();

            Console.WriteLine("Icone generee : " + path);

            WriteEmbeddableLogo(Path.Combine(Path.GetDirectoryName(path) ?? ".", "logo-embed.png"));
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("Echec de la generation de l'icone : " + ex.Message);
            return 1;
        }
    }

    // ---------------------------------------------------------------- logo fourni

    private static void LoadLogo(string path)
    {
        try
        {
            if (!File.Exists(path)) return;

            // Copie en memoire : ouvrir directement le fichier laisserait un verrou
            // dessus pendant toute la generation, et le meme fichier est ensuite
            // embarque dans l'executable par le script de compilation.
            using (Bitmap src = new Bitmap(path))
            {
                _logo = new Bitmap(src.Width, src.Height, PixelFormat.Format32bppArgb);
                using (Graphics g = Graphics.FromImage(_logo))
                {
                    g.Clear(Color.Transparent);
                    g.DrawImageUnscaled(src, 0, 0);
                }
            }
            _logoBox = AlphaBounds(_logo);
            Console.WriteLine("Logo repris de " + path);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("Logo illisible (" + ex.Message + ") : trace de secours utilise.");
            _logo = null;
        }
    }

    /// <summary>
    /// Version reduite du logo, destinee a etre embarquee dans l'executable.
    ///
    /// Le fichier d'origine fait plus d'un megaoctet - un poids justifie pour un
    /// depot, absurde pour un binaire autonome dont c'est la moitie de la taille, et
    /// ce alors que la fenetre l'affiche sur quarante pixels de haut. La reduction est
    /// faite ici plutot qu'a la main : le jour ou le logo change, personne n'a a se
    /// souvenir qu'il fallait aussi refaire la version reduite.
    ///
    /// 320 pixels de large : de quoi rester net sur un ecran a 200 % de mise a
    /// l'echelle, et de quoi servir a un usage plus grand plus tard.
    /// </summary>
    private static void WriteEmbeddableLogo(string path)
    {
        if (_logo == null) return;
        try
        {
            const int targetWidth = 320;
            if (_logoBox.Width <= targetWidth)
            {
                // Deja assez petit : autant embarquer le fichier tel quel.
                using (Bitmap exact = _logo.Clone(_logoBox, PixelFormat.Format32bppArgb))
                    exact.Save(path, ImageFormat.Png);
            }
            else
            {
                int h = Math.Max(1, (int)Math.Round(_logoBox.Height * (targetWidth / (double)_logoBox.Width)));
                using (Bitmap small = new Bitmap(targetWidth, h, PixelFormat.Format32bppArgb))
                {
                    using (Graphics g = Graphics.FromImage(small))
                    {
                        g.Clear(Color.Transparent);
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                        g.CompositingQuality = CompositingQuality.HighQuality;
                        g.DrawImage(_logo, new Rectangle(0, 0, targetWidth, h), _logoBox, GraphicsUnit.Pixel);
                    }
                    small.Save(path, ImageFormat.Png);
                }
            }
            Console.WriteLine("Logo reduit ecrit : " + path);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("Logo reduit non ecrit (" + ex.Message + ")");
        }
    }

    /// <summary>
    /// Plus petit rectangle contenant des pixels visibles.
    ///
    /// Un logo exporte porte presque toujours une marge transparente, et elle varie
    /// d'un export a l'autre. La recadrer ici plutot que de la subir garantit que
    /// l'icone occupe toujours la meme part de son cadre, quel que soit le fichier
    /// fourni.
    /// </summary>
    private static Rectangle AlphaBounds(Bitmap bmp)
    {
        Rectangle all = new Rectangle(0, 0, bmp.Width, bmp.Height);
        BitmapData data = bmp.LockBits(all, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        try
        {
            int minX = bmp.Width, minY = bmp.Height, maxX = -1, maxY = -1;
            unchecked
            {
                for (int y = 0; y < bmp.Height; y++)
                {
                    IntPtr row = (IntPtr)((long)data.Scan0 + (long)y * data.Stride);
                    for (int x = 0; x < bmp.Width; x++)
                    {
                        byte a = System.Runtime.InteropServices.Marshal.ReadByte(row, x * 4 + 3);
                        if (a <= 8) continue;
                        if (x < minX) minX = x;
                        if (x > maxX) maxX = x;
                        if (y < minY) minY = y;
                        if (y > maxY) maxY = y;
                    }
                }
            }
            if (maxX < 0) return all;
            return Rectangle.FromLTRB(minX, minY, maxX + 1, maxY + 1);
        }
        finally { bmp.UnlockBits(data); }
    }

    /// <summary>
    /// Cadre carre centre sur le dessin, occupant une fraction de sa hauteur.
    ///
    /// Le logo est nettement plus large que haut. Reduit en entier a 16 pixels, il
    /// deviendrait une ligne illisible : sous 48 pixels, on ne garde donc que le
    /// centre - la partie qui reste reconnaissable a n'importe quelle taille.
    /// </summary>
    private static Rectangle CenterSquare(Rectangle box, double fractionOfHeight)
    {
        int side = (int)Math.Round(box.Height * fractionOfHeight);
        if (side > box.Width) side = box.Width;
        int cx = box.Left + box.Width / 2;
        int cy = box.Top + box.Height / 2;
        return new Rectangle(cx - side / 2, cy - side / 2, side, side);
    }

    /// <summary>Place la source dans le cadre en gardant ses proportions.</summary>
    private static RectangleF Fit(Rectangle src, RectangleF frame)
    {
        float scale = Math.Min(frame.Width / src.Width, frame.Height / src.Height);
        float w = src.Width * scale, h = src.Height * scale;
        return new RectangleF(frame.X + (frame.Width - w) / 2f, frame.Y + (frame.Height - h) / 2f, w, h);
    }

    // ---------------------------------------------------------------- dessin

    private static Bitmap Draw(int size)
    {
        return _logo != null ? DrawFromLogo(size) : DrawFallback(size);
    }

    private static Bitmap DrawFromLogo(int size)
    {
        Bitmap bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);

        using (Graphics g = Graphics.FromImage(bmp))
        {
            g.Clear(Color.Transparent);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.CompositingQuality = CompositingQuality.HighQuality;

            // 0,62 : la fraction qui remplit le cadre du seul motif central. Mesuree,
            // pas devinee - des 0,66, les arcs de la paupiere reapparaissent dans les
            // coins et, reduits a 16 pixels, ils ne ressemblent plus qu'a du bruit.
            Rectangle src = size >= 48 ? _logoBox : CenterSquare(_logoBox, 0.62);

            // Marge franche : bord a bord, l'icone paraitrait plus grosse que ses
            // voisines dans la barre des taches, qui respirent toutes autant.
            float margin = size * 0.06f;
            RectangleF frame = new RectangleF(margin, margin, size - 2 * margin, size - 2 * margin);
            g.DrawImage(_logo, Fit(src, frame), src, GraphicsUnit.Pixel);
        }

        return bmp;
    }

    /// <summary>
    /// Un disque lumineux dont la couleur passe du bleu froid au orange chaud : les
    /// deux extremes de ce que l'application fait a l'ecran.
    ///
    /// Trace de secours, employe seulement quand aucun logo n'est fourni : une
    /// compilation ne doit jamais echouer faute d'un fichier d'illustration.
    /// </summary>
    private static Bitmap DrawFallback(int size)
    {
        Bitmap bmp = new Bitmap(size, size, PixelFormat.Format32bppArgb);

        using (Graphics g = Graphics.FromImage(bmp))
        {
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.Clear(Color.Transparent);

            // Une marge franche : bord a bord, le disque paraissait plus gros que les
            // icones voisines de la barre des taches, qui respirent toutes autant.
            float s = size;
            float margin = s * 0.16f;
            RectangleF disc = new RectangleF(margin, margin, s - 2 * margin, s - 2 * margin);

            // --- halo : ce qui distingue une source de lumiere d'une pastille de
            //     couleur. Il suit le disque, sinon il occuperait a lui seul le cadre
            //     que la marge vient de degager. ---
            using (GraphicsPath path = new GraphicsPath())
            {
                path.AddEllipse(disc.Left - disc.Width * 0.14f, disc.Top - disc.Height * 0.14f,
                                disc.Width * 1.28f, disc.Height * 1.28f);
                using (PathGradientBrush halo = new PathGradientBrush(path))
                {
                    halo.CenterColor = Color.FromArgb(150, 255, 176, 92);
                    halo.SurroundColors = new Color[] { Color.FromArgb(0, 255, 176, 92) };
                    halo.CenterPoint = new PointF(s / 2f, s / 2f);
                    g.FillPath(halo, path);
                }
            }

            // --- disque : bleu 6500 K en haut a gauche, ambre 1900 K en bas a droite.
            //     Les deux teintes restent pures a leurs extremites - un degrade etale
            //     de bout en bout donnerait un gris sans identite a 16 pixels. ---
            using (LinearGradientBrush body = new LinearGradientBrush(
                       new PointF(disc.Left, disc.Top), new PointF(disc.Right, disc.Bottom),
                       Color.FromArgb(255, 74, 158, 255), Color.FromArgb(255, 255, 152, 40)))
            {
                ColorBlend blend = new ColorBlend(4);
                blend.Colors = new Color[]
                {
                    Color.FromArgb(255,  74, 158, 255),
                    Color.FromArgb(255, 116, 182, 255),
                    Color.FromArgb(255, 255, 186,  96),
                    Color.FromArgb(255, 255, 146,  36)
                };
                blend.Positions = new float[] { 0f, 0.34f, 0.66f, 1f };
                body.InterpolationColors = blend;
                g.FillEllipse(body, disc);
            }

            // --- reflet : donne le volume sans delaver la couleur ---
            RectangleF gleam = new RectangleF(
                disc.Left + disc.Width * 0.14f, disc.Top + disc.Height * 0.10f,
                disc.Width * 0.40f, disc.Height * 0.28f);
            using (GraphicsPath path = new GraphicsPath())
            {
                path.AddEllipse(gleam);
                using (PathGradientBrush shine = new PathGradientBrush(path))
                {
                    shine.CenterColor = Color.FromArgb(110, 255, 255, 255);
                    shine.SurroundColors = new Color[] { Color.FromArgb(0, 255, 255, 255) };
                    g.FillPath(shine, path);
                }
            }

            // --- cerne : sans lui, l'icone disparait sur une barre des taches claire.
            //     Bleu nuit plutot que noir, pour ne pas salir les couleurs. Son
            //     epaisseur suit le disque, pas le cadre. ---
            float pen = Math.Max(1f, disc.Width / 20f);
            using (Pen p = new Pen(Color.FromArgb(210, 20, 26, 40), pen))
            {
                p.Alignment = PenAlignment.Inset;
                g.DrawEllipse(p, disc);
            }
        }

        return bmp;
    }

    // ---------------------------------------------------------------- ecriture du fichier .ico

    private static void Write(Stream stream, List<Bitmap> images)
    {
        List<byte[]> blobs = new List<byte[]>();
        foreach (Bitmap b in images)
        {
            // Le 256 pese 256 Ko en bitmap et dix fois moins en PNG ; l'explorateur
            // sait le lire depuis Vista. Les tailles inferieures restent en DIB :
            // System.Drawing, qui sert a poser l'icone de la fenetre, ne sait pas
            // dessiner une entree PNG et rendrait l'icone vide sur ecran a forte
            // mise a l'echelle.
            blobs.Add(b.Width >= 256 ? PngData(b) : BmpData(b));
        }

        BinaryWriter w = new BinaryWriter(stream);

        w.Write((short)0);                 // reserve
        w.Write((short)1);                 // type : 1 = icone
        w.Write((short)images.Count);

        int offset = 6 + 16 * images.Count;
        for (int i = 0; i < images.Count; i++)
        {
            Bitmap b = images[i];
            w.Write((byte)(b.Width >= 256 ? 0 : b.Width));    // 0 signifie 256
            w.Write((byte)(b.Height >= 256 ? 0 : b.Height));
            w.Write((byte)0);              // palette : aucune
            w.Write((byte)0);              // reserve
            w.Write((short)1);             // plans
            w.Write((short)32);            // bits par pixel
            w.Write(blobs[i].Length);
            w.Write(offset);
            offset += blobs[i].Length;
        }

        foreach (byte[] blob in blobs) w.Write(blob);
        w.Flush();
    }

    private static byte[] PngData(Bitmap b)
    {
        using (MemoryStream ms = new MemoryStream())
        {
            b.Save(ms, ImageFormat.Png);
            return ms.ToArray();
        }
    }

    /// <summary>
    /// Bitmap au format attendu dans un .ico : en-tete de hauteur doublee, pixels
    /// ranges du bas vers le haut, puis un masque monochrome. Le masque ne sert plus
    /// a rien avec 32 bits par pixel, mais son absence fait rejeter le fichier.
    /// </summary>
    private static byte[] BmpData(Bitmap b)
    {
        int width = b.Width, height = b.Height;
        int maskRow = ((width + 31) / 32) * 4;

        using (MemoryStream ms = new MemoryStream())
        {
            BinaryWriter w = new BinaryWriter(ms);

            w.Write(40);                   // taille de l'en-tete
            w.Write(width);
            w.Write(height * 2);           // image + masque
            w.Write((short)1);
            w.Write((short)32);
            w.Write(0);                    // sans compression
            w.Write(width * height * 4 + maskRow * height);
            w.Write(0); w.Write(0);        // resolution
            w.Write(0); w.Write(0);        // palette

            for (int y = height - 1; y >= 0; y--)
            {
                for (int x = 0; x < width; x++)
                {
                    Color c = b.GetPixel(x, y);
                    w.Write(c.B); w.Write(c.G); w.Write(c.R); w.Write(c.A);
                }
            }

            byte[] emptyRow = new byte[maskRow];
            for (int y = 0; y < height; y++) w.Write(emptyRow);

            w.Flush();
            return ms.ToArray();
        }
    }
}
