using System;
using System.Drawing;
using System.Windows.Forms;

namespace LumaFlux
{
    /// <summary>
    /// Confirmation a rebours, calquee sur ce que fait Windows lors d'un changement de
    /// resolution : si l'ecran est devenu illisible, il suffit de ne rien faire pour
    /// que le reglage precedent revienne tout seul.
    ///
    /// C'est la protection la plus importante contre l'ecran noir, parce que c'est la
    /// seule qui fonctionne quand l'utilisateur ne voit plus rien du tout.
    /// </summary>
    public class ConfirmDialog : Form
    {
        private readonly Timer _timer = new Timer();
        private int _remaining;
        private readonly Label _countdown = new Label();
        private readonly CheckBox _dontAsk = new CheckBox();

        public bool DontAskAgain { get { return _dontAsk.Checked; } }

        public ConfirmDialog(double brightness, int seconds)
        {
            _remaining = seconds;

            Text = "Garder ce reglage ?";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterScreen;
            MaximizeBox = false;
            MinimizeBox = false;
            ShowInTaskbar = false;
            TopMost = true;
            ClientSize = new Size(420, 210);
            BackColor = Color.FromArgb(250, 250, 252);
            Font = new Font("Segoe UI", 9f);

            Label title = new Label();
            title.Text = string.Format("Luminosite reglee sur {0} %", Math.Round(brightness));
            title.Font = new Font("Segoe UI", 12f, FontStyle.Bold);
            title.ForeColor = Color.FromArgb(30, 34, 42);
            title.SetBounds(24, 20, 380, 28);
            Controls.Add(title);

            Label body = new Label();
            body.Text = "Si l'ecran est devenu trop sombre pour etre lisible, ne touchez a rien : "
                      + "le reglage precedent sera retabli automatiquement.";
            body.ForeColor = Color.FromArgb(80, 86, 98);
            body.SetBounds(24, 52, 375, 40);
            Controls.Add(body);

            _countdown.Font = new Font("Segoe UI", 9f);
            _countdown.ForeColor = Color.FromArgb(120, 126, 140);
            _countdown.SetBounds(24, 100, 380, 22);
            Controls.Add(_countdown);

            _dontAsk.Text = "Ne plus me demander";
            _dontAsk.ForeColor = Color.FromArgb(80, 86, 98);
            _dontAsk.SetBounds(24, 126, 220, 24);
            Controls.Add(_dontAsk);

            Button keep = new Button();
            keep.Text = "Garder";
            keep.SetBounds(214, 160, 90, 32);
            keep.DialogResult = DialogResult.OK;
            keep.FlatStyle = FlatStyle.System;
            Controls.Add(keep);

            Button revert = new Button();
            revert.Text = "Annuler";
            revert.SetBounds(312, 160, 90, 32);
            revert.DialogResult = DialogResult.Cancel;
            revert.FlatStyle = FlatStyle.System;
            Controls.Add(revert);

            AcceptButton = keep;
            CancelButton = revert;

            UpdateCountdown();
            _timer.Interval = 1000;
            _timer.Tick += Tick;
            _timer.Start();
        }

        private void Tick(object sender, EventArgs e)
        {
            _remaining--;
            UpdateCountdown();
            if (_remaining <= 0)
            {
                _timer.Stop();
                DialogResult = DialogResult.Cancel;   // sans reponse : on revient en arriere
                Close();
            }
        }

        private void UpdateCountdown()
        {
            _countdown.Text = string.Format(
                "Retour automatique au reglage precedent dans {0} seconde{1}.",
                _remaining, _remaining > 1 ? "s" : "");
        }

        protected override void Dispose(bool disposing)
        {
            if (disposing && _timer != null) { _timer.Stop(); _timer.Dispose(); }
            base.Dispose(disposing);
        }
    }
}
