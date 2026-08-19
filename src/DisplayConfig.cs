using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace OpusScreen
{
    /// <summary>
    /// Ce que Windows sait vraiment de chaque ecran, via l'API DisplayConfig.
    ///
    /// Pourquoi ne pas se contenter de EnumDisplayDevices : cette fonction renvoie
    /// le nom du PILOTE, presque toujours « Generic PnP Monitor », et un identifiant
    /// materiel qui ne contient que le MODELE. Deux ecrans identiques - le cas le plus
    /// banal d'une configuration a deux ecrans - portent donc exactement le meme
    /// identifiant. Tout ce qui est memorise par ecran finit alors dans la meme case :
    /// regler le second revient a regler le premier, et le voile de l'un recouvre
    /// l'autre.
    ///
    /// DisplayConfig donne trois choses qui manquaient :
    ///
    ///   - monitorFriendlyDeviceName : le nom EDID, celui grave dans l'ecran
    ///   - monitorDevicePath         : un chemin unique par connecteur
    ///   - outputTechnology          : de quoi reconnaitre la dalle interne d'un
    ///                                 portable, seule a repondre au reglage WMI
    ///
    /// L'API existe depuis Windows 7. En cas d'echec - session distante, pilote
    /// exotique - l'appelant retombe sur l'ancienne methode : moins precise, jamais
    /// bloquante.
    /// </summary>
    public static class DisplayConfig
    {
        /// <summary>Un ecran vu par DisplayConfig, indexe par son nom GDI.</summary>
        public class Target
        {
            public string GdiDeviceName = "";   // "\\.\DISPLAY1", la clef de rapprochement
            public string FriendlyName = "";    // "DELL U2412M"
            public string DevicePath = "";      // unique par connecteur
            public uint ConnectorInstance;      // numero du connecteur sur la carte
            public bool IsInternal;             // dalle integree d'un portable
            public uint OutputTechnology;
        }

        // ---------------------------------------------------------------- structures

        [StructLayout(LayoutKind.Sequential)]
        private struct LUID { public uint LowPart; public int HighPart; }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_RATIONAL { public uint Numerator; public uint Denominator; }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_PATH_SOURCE_INFO
        {
            public LUID adapterId;
            public uint id;
            public uint modeInfoIdx;
            public uint statusFlags;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_PATH_TARGET_INFO
        {
            public LUID adapterId;
            public uint id;
            public uint modeInfoIdx;
            public uint outputTechnology;
            public uint rotation;
            public uint scaling;
            public DISPLAYCONFIG_RATIONAL refreshRate;
            public uint scanLineOrdering;
            public int targetAvailable;      // BOOL : declare en int pour figer les 4 octets
            public uint statusFlags;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_PATH_INFO
        {
            public DISPLAYCONFIG_PATH_SOURCE_INFO sourceInfo;
            public DISPLAYCONFIG_PATH_TARGET_INFO targetInfo;
            public uint flags;
        }

        /// <summary>
        /// Les modes ne sont pas exploites ici, mais le tableau doit exister et faire
        /// la bonne taille : l'API ecrit dedans. Les 64 octets sont donc reserves
        /// champ par champ plutot que devines.
        /// </summary>
        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_MODE_INFO
        {
            public uint infoType;
            public uint id;
            public LUID adapterId;
            public ulong u0, u1, u2, u3, u4, u5;   // union de 48 octets
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct DISPLAYCONFIG_DEVICE_INFO_HEADER
        {
            public uint type;
            public uint size;
            public LUID adapterId;
            public uint id;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DISPLAYCONFIG_TARGET_DEVICE_NAME
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            public uint flags;
            public uint outputTechnology;
            public ushort edidManufactureId;
            public ushort edidProductCodeId;
            public uint connectorInstance;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)] public string monitorFriendlyDeviceName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)] public string monitorDevicePath;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct DISPLAYCONFIG_SOURCE_DEVICE_NAME
        {
            public DISPLAYCONFIG_DEVICE_INFO_HEADER header;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string viewGdiDeviceName;
        }

        [DllImport("user32.dll")]
        private static extern int GetDisplayConfigBufferSizes(uint flags, out uint numPaths, out uint numModes);

        [DllImport("user32.dll")]
        private static extern int QueryDisplayConfig(uint flags,
            ref uint numPaths, [Out] DISPLAYCONFIG_PATH_INFO[] paths,
            ref uint numModes, [Out] DISPLAYCONFIG_MODE_INFO[] modes,
            IntPtr currentTopologyId);

        [DllImport("user32.dll")]
        private static extern int DisplayConfigGetDeviceInfo(ref DISPLAYCONFIG_TARGET_DEVICE_NAME request);

        [DllImport("user32.dll", EntryPoint = "DisplayConfigGetDeviceInfo")]
        private static extern int DisplayConfigGetSourceName(ref DISPLAYCONFIG_SOURCE_DEVICE_NAME request);

        private const uint QDC_ONLY_ACTIVE_PATHS = 0x00000002;
        private const int ERROR_SUCCESS = 0;
        private const uint GET_SOURCE_NAME = 1;
        private const uint GET_TARGET_NAME = 2;

        // Technologies de sortie correspondant a une dalle integree. Le fabricant
        // choisit laquelle declarer : les quatre doivent etre reconnues.
        private const uint OUT_LVDS = 6;
        private const uint OUT_DISPLAYPORT_EMBEDDED = 11;
        private const uint OUT_UDI_EMBEDDED = 13;
        private const uint OUT_INTERNAL = 0x80000000;

        // ---------------------------------------------------------------- interrogation

        /// <summary>
        /// Les ecrans actifs, indexes par nom GDI. Dictionnaire vide si l'API echoue :
        /// l'appelant garde alors ses valeurs par defaut au lieu de perdre un ecran.
        /// </summary>
        public static Dictionary<string, Target> Query()
        {
            Dictionary<string, Target> byGdiName = new Dictionary<string, Target>(StringComparer.OrdinalIgnoreCase);

            try
            {
                uint pathCount, modeCount;
                if (GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, out pathCount, out modeCount) != ERROR_SUCCESS)
                    return byGdiName;
                if (pathCount == 0) return byGdiName;

                DISPLAYCONFIG_PATH_INFO[] paths = new DISPLAYCONFIG_PATH_INFO[pathCount];
                DISPLAYCONFIG_MODE_INFO[] modes = new DISPLAYCONFIG_MODE_INFO[modeCount];

                if (QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, ref pathCount, paths,
                                       ref modeCount, modes, IntPtr.Zero) != ERROR_SUCCESS)
                    return byGdiName;

                for (int i = 0; i < pathCount; i++)
                {
                    Target t = Describe(paths[i]);
                    if (t == null || t.GdiDeviceName.Length == 0) continue;

                    // Clonage d'ecrans : plusieurs cibles derriere une meme source.
                    // La premiere l'emporte, c'est celle que pilotent les APIs GDI.
                    if (!byGdiName.ContainsKey(t.GdiDeviceName)) byGdiName[t.GdiDeviceName] = t;
                }
            }
            catch { /* API absente ou refusee : dictionnaire vide, repli en amont */ }

            return byGdiName;
        }

        private static Target Describe(DISPLAYCONFIG_PATH_INFO path)
        {
            Target t = new Target();

            DISPLAYCONFIG_SOURCE_DEVICE_NAME src = new DISPLAYCONFIG_SOURCE_DEVICE_NAME();
            src.header.type = GET_SOURCE_NAME;
            src.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_SOURCE_DEVICE_NAME));
            src.header.adapterId = path.sourceInfo.adapterId;
            src.header.id = path.sourceInfo.id;
            if (DisplayConfigGetSourceName(ref src) != ERROR_SUCCESS) return null;
            t.GdiDeviceName = (src.viewGdiDeviceName ?? "").Trim();

            DISPLAYCONFIG_TARGET_DEVICE_NAME tgt = new DISPLAYCONFIG_TARGET_DEVICE_NAME();
            tgt.header.type = GET_TARGET_NAME;
            tgt.header.size = (uint)Marshal.SizeOf(typeof(DISPLAYCONFIG_TARGET_DEVICE_NAME));
            tgt.header.adapterId = path.targetInfo.adapterId;
            tgt.header.id = path.targetInfo.id;

            if (DisplayConfigGetDeviceInfo(ref tgt) == ERROR_SUCCESS)
            {
                t.FriendlyName = (tgt.monitorFriendlyDeviceName ?? "").Trim();
                t.DevicePath = (tgt.monitorDevicePath ?? "").Trim();
                t.ConnectorInstance = tgt.connectorInstance;
                t.OutputTechnology = tgt.outputTechnology;
            }
            else
            {
                t.OutputTechnology = path.targetInfo.outputTechnology;
            }

            t.IsInternal = t.OutputTechnology == OUT_INTERNAL
                        || t.OutputTechnology == OUT_LVDS
                        || t.OutputTechnology == OUT_DISPLAYPORT_EMBEDDED
                        || t.OutputTechnology == OUT_UDI_EMBEDDED;

            // Un portable dont le fabricant n'a rien declare : le nom EDID est vide
            // et la technologie inconnue. Mieux vaut un intitule lisible qu'un vide.
            if (t.FriendlyName.Length == 0)
                t.FriendlyName = t.IsInternal ? "Ecran integre" : "";

            return t;
        }

        /// <summary>
        /// Nom lisible de la connectique, pour que l'utilisateur reconnaisse
        /// physiquement l'ecran dont on lui parle.
        /// </summary>
        public static string ConnectionName(uint outputTechnology)
        {
            switch (outputTechnology)
            {
                case 0: return "VGA";
                case 4: return "DVI";
                case 5: return "HDMI";
                case OUT_LVDS: return "dalle interne";
                case 10: return "DisplayPort";
                case OUT_DISPLAYPORT_EMBEDDED: return "dalle interne";
                case 12: return "UDI";
                case OUT_UDI_EMBEDDED: return "dalle interne";
                case 15: return "Miracast";
                case 16: return "affichage indirect";
                case 17: return "affichage virtuel";
                case OUT_INTERNAL: return "dalle interne";
                default: return "";
            }
        }
    }
}
