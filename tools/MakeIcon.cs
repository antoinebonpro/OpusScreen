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

    private static int Main(string[] args)
    {
        string path = Path.GetFullPath(args.Length > 0 ? args[0] : "OpusScreen.ico");

        try
        {
            string dir = Path.GetDirectoryName(path);
            if (dir.Length > 0) Directory.CreateDirectory(dir);

            List<Bitmap> images = new List<Bitmap>();
            foreach (int s in Sizes) images.Add(Draw(s));

            using (FileStream fs = new FileStream(path, FileMode.Create, FileAccess.Write))
                Write(fs, images);

            foreach (Bitmap b in images) b.Dispose();

            Console.WriteLine("Icone generee : " + path);
            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine("Echec de la generation de l'icone : " + ex.Message);
            return 1;
        }
    }

    // ---------------------------------------------------------------- dessin

    /// <summary>
    /// Un disque lumineux dont la couleur passe du bleu froid au orange chaud : les
    /// deux extremes de ce que l'application fait a l'ecran. Le meme langage visuel
    /// que l'icone de la zone de notification, en version fixe.
    /// </summary>
    private static Bitmap Draw(int size)
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
