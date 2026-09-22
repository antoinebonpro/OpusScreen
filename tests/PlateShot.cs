using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;
using OpusScreen;

/// <summary>
/// Outil d'observation : dessine les planches du test dans une image, pour les
/// regarder a l'oeil. Le calcul dit qu'elles cachent bien leur chiffre ; l'image dit
/// si elles ressemblent a quelque chose.
///
/// Usage : PlateShot.exe chemin.png [graine]
/// </summary>
class PlateShot
{
    [STAThread]
    static void Main(string[] args)
    {
        string path = args.Length > 0 ? args[0] : "planches.png";
        int seed = args.Length > 1 ? int.Parse(args[1]) : 7;

        List<VisionPlate> plates = VisionExam.Plates(seed);
        const int side = 260, gap = 12, perRow = 4;
        int rows = (plates.Count + perRow - 1) / perRow;

        using (Bitmap sheet = new Bitmap(perRow * (side + gap) + gap, rows * (side + gap + 22) + gap))
        using (Graphics g = Graphics.FromImage(sheet))
        {
            g.Clear(Theme.Card);
            for (int i = 0; i < plates.Count; i++)
            {
                PlateView view = new PlateView();
                view.Size = new Size(side, side);
                view.Show(plates[i]);

                using (Bitmap b = new Bitmap(side, side))
                {
                    view.DrawToBitmap(b, new Rectangle(0, 0, side, side));
                    int x = gap + (i % perRow) * (side + gap);
                    int y = gap + (i / perRow) * (side + gap + 22);
                    g.DrawImage(b, x, y);

                    string label = plates[i].Axis == ColorFilter.None
                        ? "controle - chiffre " + plates[i].Digit
                        : Vision.PlainName(plates[i].Axis) + " " + plates[i].Level + " % - chiffre " + plates[i].Digit;
                    using (Font f = new Font("Arial", 11))
                    using (SolidBrush br = new SolidBrush(Theme.Fg))
                        g.DrawString(label, f, br, x, y + side + 2);
                }
                view.Dispose();
            }
            sheet.Save(path, System.Drawing.Imaging.ImageFormat.Png);
        }
        Console.WriteLine("Ecrit : " + path);
    }
}
