using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;

namespace OpusScreen
{
    /// <summary>
    /// Presence dans la barre des taches et le menu Demarrer.
    ///
    /// Windows n'epingle pas un executable, il epingle un raccourci. Sans raccourci
    /// depose par l'application, ce que l'utilisateur epingle est un fichier isole :
    /// nom tronque, description absente, et une entree qui ne se relie a rien. On
    /// depose donc un raccourci dans le menu Demarrer et on garde sa cible a jour.
    ///
    /// Aucun identifiant d'application explicite n'est pose. Windows en derive un du
    /// chemin de l'executable, et c'est exactement ce qui fait que la fenetre vient se
    /// ranger sous l'icone epinglee - qu'elle provienne de notre raccourci ou d'un
    /// clic droit sur l'executable. Un identifiant maison creerait au contraire deux
    /// boutons cote a cote pour un seul programme.
    /// </summary>
    public static class Taskbar
    {
        public static string ExecutablePath
        {
            get
            {
                try
                {
                    string p = Assembly.GetExecutingAssembly().Location;
                    if (!string.IsNullOrEmpty(p)) return p;
                }
                catch { }
                return System.Windows.Forms.Application.ExecutablePath;
            }
        }

        /// <summary>Raccourci du menu Demarrer de l'utilisateur courant.</summary>
        public static string ShortcutPath
        {
            get
            {
                return Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.Programs),
                    "OpusScreen.lnk");
            }
        }

        // ------------------------------------------------------------------ raccourci

        /// <summary>
        /// Cree le raccourci du menu Demarrer, ou corrige sa cible si l'executable a
        /// change de dossier depuis. Retourne vrai si le raccourci est en place.
        /// </summary>
        public static bool EnsureShortcut()
        {
            try
            {
                string exe = ExecutablePath;
                if (!File.Exists(exe)) return false;

                RemoveLegacyShortcut();

                string lnk = ShortcutPath;
                if (File.Exists(lnk))
                {
                    string target = ReadShortcutTarget(lnk);
                    if (string.Equals(target, exe, StringComparison.OrdinalIgnoreCase)) return true;
                }

                Directory.CreateDirectory(Path.GetDirectoryName(lnk));
                WriteShortcut(lnk, "", "Luminosite, temperature de couleur et confort visuel");
                return true;
            }
            catch { return false; }
        }

        /// <summary>
        /// Efface le raccourci laisse par LumaFlux. Sa cible n'existe plus apres le
        /// changement de nom : le menu Demarrer afficherait une entree morte a cote de
        /// la bonne. Seul un raccourci pointant vers l'ancien executable est retire.
        /// </summary>
        private static void RemoveLegacyShortcut()
        {
            try
            {
                string legacy = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.Programs),
                    "LumaFlux.lnk");

                if (!File.Exists(legacy)) return;

                string target = ReadShortcutTarget(legacy);
                if (!string.IsNullOrEmpty(target)
                    && target.EndsWith("LumaFlux.exe", StringComparison.OrdinalIgnoreCase))
                    File.Delete(legacy);
            }
            catch { }
        }

        /// <summary>Ouvre l'explorateur sur le raccourci, deja selectionne.</summary>
        public static void RevealShortcut()
        {
            try
            {
                string lnk = ShortcutPath;
                if (File.Exists(lnk))
                    System.Diagnostics.Process.Start("explorer.exe", "/select,\"" + lnk + "\"");
                else
                    System.Diagnostics.Process.Start("explorer.exe", "\"" + Path.GetDirectoryName(ExecutablePath) + "\"");
            }
            catch { }
        }

        /// <summary>
        /// Tente l'epinglage automatique. Windows 10 version 1607 a retire ce verbe du
        /// menu contextuel programmable, et Windows 11 ne l'expose plus du tout : sur
        /// ces versions la reponse est non, et il faut passer par l'utilisateur.
        /// </summary>
        public static bool TryPin()
        {
            try
            {
                string lnk = ShortcutPath;
                if (!File.Exists(lnk)) return false;

                Type shellType = Type.GetTypeFromProgID("Shell.Application");
                if (shellType == null) return false;

                object shell = Activator.CreateInstance(shellType);
                object folder = Call(shell, "NameSpace", Path.GetDirectoryName(lnk));
                if (folder == null) return false;
                object item = Call(folder, "ParseName", Path.GetFileName(lnk));
                if (item == null) return false;
                object verbs = Call(item, "Verbs");
                if (verbs == null) return false;

                int count = (int)Get(verbs, "Count");
                for (int i = 0; i < count; i++)
                {
                    object verb = Call(verbs, "Item", i);
                    string name = (string)Get(verb, "Name");
                    if (IsPinVerb(name)) { Call(verb, "DoIt"); return true; }
                }
            }
            catch { }
            return false;
        }

        /// <summary>
        /// Reconnait le verbe « Epingler a la barre des taches » parmi ceux du menu
        /// contextuel, dont les libelles sont traduits.
        ///
        /// Le detachement porte exactement les memes mots - « Desepingler de la barre
        /// des taches » - et c'est justement le seul des deux que Windows 11 expose
        /// encore. Le rejet doit donc primer sur la reconnaissance : une comparaison
        /// naive epinglerait a l'envers.
        /// </summary>
        public static bool IsPinVerb(string verbName)
        {
            string n = Flatten(verbName);

            if (n.IndexOf("taskbar") < 0 && n.IndexOf("barre des t") < 0) return false;

            if (n.IndexOf("unpin") >= 0 || n.IndexOf("desepingl") >= 0 || n.IndexOf("detach") >= 0
             || n.IndexOf("remove") >= 0 || n.IndexOf("supprim") >= 0 || n.IndexOf("retir") >= 0)
                return false;

            return n.IndexOf("pin") >= 0;
        }

        /// <summary>
        /// Minuscules sans accent ni raccourci clavier. Permet de comparer a des mots
        /// ecrits sans accent, ce que le code source de ce projet impose.
        /// </summary>
        private static string Flatten(string text)
        {
            string d = text.Replace("&", "").Normalize(NormalizationForm.FormD);
            StringBuilder sb = new StringBuilder(d.Length);
            foreach (char c in d)
            {
                if (CharUnicodeInfo.GetUnicodeCategory(c) != UnicodeCategory.NonSpacingMark)
                    sb.Append(c);
            }
            return sb.ToString().ToLowerInvariant();
        }

        private static object Call(object target, string method, params object[] args)
        {
            return target.GetType().InvokeMember(method, BindingFlags.InvokeMethod, null, target, args);
        }

        private static object Get(object target, string property)
        {
            return target.GetType().InvokeMember(property, BindingFlags.GetProperty, null, target, null);
        }

        // ------------------------------------------------------------------ liste de raccourcis

        /// <summary>
        /// Taches proposees au clic droit sur l'icone de la barre des taches.
        ///
        /// Chacune relance l'executable avec un argument : le pilotage en ligne de
        /// commande existait deja et transmet l'ordre a l'instance en cours, il n'y a
        /// donc rien de neuf a construire cote application.
        /// </summary>
        public static bool PublishJumpList(bool suspended)
        {
            ICustomDestinationList list = null;
            IObjectCollection tasks = null;

            try
            {
                list = (ICustomDestinationList)new DestinationList();

                uint slots;
                object removed;
                Guid iidArray = IID_IObjectArray;
                list.BeginList(out slots, ref iidArray, out removed);

                tasks = (IObjectCollection)new EnumerableObjectCollection();

                Add(tasks, "Ouvrir les reglages", "--show");
                if (suspended) Add(tasks, "Reprendre les effets", "--resume");
                else Add(tasks, "Suspendre les effets", "--pause");
                Add(tasks, "Pause pour les yeux", "--break");

                AddSeparator(tasks);

                Add(tasks, "Mode Confort", "--mode \"Confort\"");
                Add(tasks, "Mode Nuit profonde", "--mode \"Nuit profonde\"");
                Add(tasks, "Mode Plein soleil", "--mode \"Plein soleil\"");

                AddSeparator(tasks);

                Add(tasks, "Retablir un ecran normal", "--reset");

                list.AddUserTasks((IObjectArray)tasks);
                list.CommitList();
                return true;
            }
            catch
            {
                // Avant Windows 7, ou si le shell refuse : l'application marche pareil.
                try { if (list != null) list.AbortList(); }
                catch { }
                return false;
            }
            finally
            {
                Release(tasks);
                Release(list);
            }
        }

        /// <summary>Retire la liste de taches publiee par ce programme.</summary>
        public static bool ClearJumpList()
        {
            ICustomDestinationList list = null;
            try
            {
                list = (ICustomDestinationList)new DestinationList();
                list.DeleteList(null);
                return true;
            }
            catch { return false; }
            finally { Release(list); }
        }

        private static void Add(IObjectCollection tasks, string title, string arguments)
        {
            IShellLinkW link = (IShellLinkW)new ShellLink();
            link.SetPath(ExecutablePath);
            link.SetArguments(arguments);
            link.SetIconLocation(ExecutablePath, 0);
            link.SetWorkingDirectory(Path.GetDirectoryName(ExecutablePath));
            link.SetDescription(title);

            // Sans titre explicite, le shell affiche le nom du fichier cible pour
            // chacune des taches, et la liste devient une colonne de « OpusScreen ».
            IPropertyStore store = (IPropertyStore)link;
            PropVariant value = PropVariant.FromString(title);
            try
            {
                PropertyKey key = PKEY_Title;
                store.SetValue(ref key, ref value);
                store.Commit();
            }
            finally { value.Clear(); }

            tasks.AddObject(link);
            Release(store);
            Release(link);
        }

        private static void AddSeparator(IObjectCollection tasks)
        {
            IShellLinkW link = (IShellLinkW)new ShellLink();
            link.SetPath(ExecutablePath);

            IPropertyStore store = (IPropertyStore)link;
            PropVariant value = PropVariant.FromBool(true);
            try
            {
                PropertyKey key = PKEY_IsDestListSeparator;
                store.SetValue(ref key, ref value);
                store.Commit();
            }
            finally { value.Clear(); }

            tasks.AddObject(link);
            Release(store);
            Release(link);
        }

        private static void Release(object com)
        {
            try { if (com != null && Marshal.IsComObject(com)) Marshal.ReleaseComObject(com); }
            catch { }
        }

        // ------------------------------------------------------------------ ecriture du .lnk

        /// <summary>Ecrit un raccourci vers l'executable courant.</summary>
        public static void WriteShortcut(string lnkPath, string arguments, string description)
        {
            string target = ExecutablePath;
            IShellLinkW link = (IShellLinkW)new ShellLink();
            try
            {
                link.SetPath(target);
                link.SetArguments(arguments);
                link.SetWorkingDirectory(Path.GetDirectoryName(target));
                link.SetIconLocation(target, 0);
                link.SetDescription(description);
                ((IPersistFile)link).Save(lnkPath, true);
            }
            finally { Release(link); }
        }

        /// <summary>Cible d'un raccourci, ou chaine vide s'il est illisible.</summary>
        public static string ReadShortcutTarget(string lnkPath)
        {
            IShellLinkW link = (IShellLinkW)new ShellLink();
            try
            {
                ((IPersistFile)link).Load(lnkPath, 0);
                StringBuilder sb = new StringBuilder(600);
                link.GetPath(sb, sb.Capacity, IntPtr.Zero, 0);
                return sb.ToString();
            }
            catch { return ""; }
            finally { Release(link); }
        }

        // ------------------------------------------------------------------ declarations COM

        private static readonly Guid IID_IObjectArray = new Guid("92CA9DCD-5622-4BBA-A805-5E9F541BD8C9");

        private static readonly PropertyKey PKEY_Title = new PropertyKey(
            new Guid("F29F85E0-4FF9-1068-AB91-08002B27B3D9"), 2);

        private static readonly PropertyKey PKEY_IsDestListSeparator = new PropertyKey(
            new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), 6);

        [ComImport, Guid("00021401-0000-0000-C000-000000000046")]
        private class ShellLink { }

        [ComImport, Guid("2D3468C1-36A7-43B6-AC24-D3F02FD9607A")]
        private class EnumerableObjectCollection { }

        [ComImport, Guid("77F10CF0-3DB5-4966-B520-B7C54FD35ED6")]
        private class DestinationList { }

        [StructLayout(LayoutKind.Sequential, Pack = 4)]
        private struct PropertyKey
        {
            public Guid FormatId;
            public int PropertyId;
            public PropertyKey(Guid formatId, int propertyId)
            {
                FormatId = formatId;
                PropertyId = propertyId;
            }
        }

        /// <summary>
        /// PROPVARIANT reduit aux deux formes utilisees ici : chaine et booleen.
        /// La disposition suit celle de Windows - quatre entiers courts puis une union
        /// large d'un pointeur - ce qui donne 16 octets en 32 bits et 24 en 64 bits.
        /// </summary>
        [StructLayout(LayoutKind.Sequential)]
        private struct PropVariant
        {
            private ushort _type;
            private ushort _r1, _r2, _r3;
            private IntPtr _value;
            private IntPtr _value2;

            private const ushort VT_LPWSTR = 31;
            private const ushort VT_BOOL = 11;

            public static PropVariant FromString(string text)
            {
                PropVariant v = new PropVariant();
                v._type = VT_LPWSTR;
                v._value = Marshal.StringToCoTaskMemUni(text);
                return v;
            }

            public static PropVariant FromBool(bool value)
            {
                PropVariant v = new PropVariant();
                v._type = VT_BOOL;
                // VARIANT_BOOL : -1 pour vrai, 0 pour faux.
                v._value = new IntPtr(value ? -1 : 0);
                return v;
            }

            public void Clear()
            {
                if (_type == VT_LPWSTR && _value != IntPtr.Zero)
                {
                    Marshal.FreeCoTaskMem(_value);
                    _value = IntPtr.Zero;
                }
            }
        }

        [ComImport, Guid("000214F9-0000-0000-C000-000000000046"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IShellLinkW
        {
            void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder file, int cch,
                         IntPtr findData, uint flags);
            void GetIDList(out IntPtr pidl);
            void SetIDList(IntPtr pidl);
            void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder name, int cch);
            void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string name);
            void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder dir, int cch);
            void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string dir);
            void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder args, int cch);
            void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string args);
            void GetHotkey(out short hotkey);
            void SetHotkey(short hotkey);
            void GetShowCmd(out int show);
            void SetShowCmd(int show);
            void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder icon, int cch,
                                 out int index);
            void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string icon, int index);
            void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string path, uint reserved);
            void Resolve(IntPtr hwnd, uint flags);
            void SetPath([MarshalAs(UnmanagedType.LPWStr)] string path);
        }

        [ComImport, Guid("0000010B-0000-0000-C000-000000000046"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPersistFile
        {
            void GetClassID(out Guid classId);
            [PreserveSig] int IsDirty();
            void Load([MarshalAs(UnmanagedType.LPWStr)] string file, uint mode);
            void Save([MarshalAs(UnmanagedType.LPWStr)] string file,
                      [MarshalAs(UnmanagedType.Bool)] bool remember);
            void SaveCompleted([MarshalAs(UnmanagedType.LPWStr)] string file);
            void GetCurFile([MarshalAs(UnmanagedType.LPWStr)] out string file);
        }

        [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IPropertyStore
        {
            void GetCount(out uint count);
            void GetAt(uint index, out PropertyKey key);
            void GetValue(ref PropertyKey key, out PropVariant value);
            void SetValue(ref PropertyKey key, ref PropVariant value);
            void Commit();
        }

        // Les deux interfaces sont declarees a plat plutot que par heritage : le
        // passage de l'une a l'autre se fait par conversion, que le pont COM traduit
        // en QueryInterface.
        [ComImport, Guid("92CA9DCD-5622-4BBA-A805-5E9F541BD8C9"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IObjectArray
        {
            void GetCount(out uint count);
            void GetAt(uint index, ref Guid riid,
                       [MarshalAs(UnmanagedType.Interface)] out object item);
        }

        [ComImport, Guid("5632B1A4-E38A-400A-928A-D4CD63230295"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface IObjectCollection
        {
            void GetCount(out uint count);
            void GetAt(uint index, ref Guid riid,
                       [MarshalAs(UnmanagedType.Interface)] out object item);
            void AddObject([MarshalAs(UnmanagedType.Interface)] object item);
            void AddFromArray(IObjectArray source);
            void RemoveObjectAt(uint index);
            void Clear();
        }

        [ComImport, Guid("6332DEBF-87B5-4670-90C0-5E57B408A49E"),
         InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        private interface ICustomDestinationList
        {
            void SetAppID([MarshalAs(UnmanagedType.LPWStr)] string appId);
            void BeginList(out uint maxSlots, ref Guid riid,
                           [MarshalAs(UnmanagedType.Interface)] out object items);
            void AppendCategory([MarshalAs(UnmanagedType.LPWStr)] string category, IObjectArray items);
            void AppendKnownCategory(int category);
            void AddUserTasks(IObjectArray items);
            void CommitList();
            void GetRemovedDestinations(ref Guid riid,
                                        [MarshalAs(UnmanagedType.Interface)] out object items);
            void DeleteList([MarshalAs(UnmanagedType.LPWStr)] string appId);
            void AbortList();
        }
    }
}
