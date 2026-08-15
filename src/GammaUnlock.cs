using Microsoft.Win32;

namespace LumaFlux
{
    /// <summary>
    /// Depuis Windows Vista, GDI rabote les courbes gamma trop eloignees de la lineaire.
    /// C'est pour cette raison qu'un boost logiciel semble parfois sans effet, alors que
    /// SetDeviceGammaRamp a pourtant repondu "succes".
    ///
    /// La valeur GdiIcmGammaRange leve cette limite. Elle est en HKLM, donc reservee a
    /// l'administrateur, et n'est lue qu'a l'ouverture de session.
    /// </summary>
    public static class GammaUnlock
    {
        private const string KeyPath = @"SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM";
        private const string ValueName = "GdiIcmGammaRange";

        /// <summary>Vrai si la plage complete est deja autorisee.</summary>
        public static bool IsUnlocked()
        {
            try
            {
                using (RegistryKey k = Registry.LocalMachine.OpenSubKey(KeyPath))
                {
                    if (k == null) return false;
                    object v = k.GetValue(ValueName);
                    return v != null && (int)v == 256;
                }
            }
            catch { return false; }
        }

        /// <summary>Ecrit la valeur. Retourne false sans droits administrateur.</summary>
        public static bool TryUnlock()
        {
            try
            {
                using (RegistryKey k = Registry.LocalMachine.CreateSubKey(KeyPath))
                {
                    if (k == null) return false;
                    k.SetValue(ValueName, 256, RegistryValueKind.DWord);
                    return true;
                }
            }
            catch { return false; }
        }
    }
}
