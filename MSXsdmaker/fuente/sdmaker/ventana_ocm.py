"""ventana_ocm.py — el menu de las BIOS del MSXBOOK / OneChipBook / 1chipMSX: las que lleva la tarjeta (la principal,
OCM-BIOS.DAT, y las de reserva, ALT-BIOS.DA0-.DA9) y, de cada una, las opciones de make-sdb.cmd de KdL: tipo de
maquina, disco (Nextor o MegaSDHC), teclado, logo (con su imagen), WiFi, logo del turboR y Extra-ROM."""
import base64
import copy
import tkinter as tk
from tkinter import messagebox, ttk

from . import ocm


class DialogoBios:
    def __init__(self, padre, pack, lista):
        self.pack = pack
        self.lista = copy.deepcopy(lista)
        self.resultado = None
        self.actual = 0
        self.cargando = False
        self.imagen = None
        self.top = tk.Toplevel(padre)
        self.top.title("BIOS de la tarjeta (%s)" % pack.texto())
        self.top.transient(padre)
        self.top.resizable(False, False)
        self.v = {"tipo": tk.StringVar(), "disco": tk.StringVar(), "teclado": tk.StringVar(), "logo": tk.StringVar(),
                  "wifi": tk.BooleanVar(), "logo_tr": tk.BooleanVar(), "extra": tk.StringVar()}
        self.nombre = tk.StringVar()
        self._construir()
        self._rellenar_lista()
        self._elegir(0)
        for var in self.v.values():
            var.trace_add("write", lambda *a: self._cambio())
        self.top.grab_set()
        self.top.wait_window()

    # ------------------------------------------------------------------ interfaz
    def _construir(self):
        p = {"padx": 8, "pady": 4}
        cuerpo = ttk.Frame(self.top)
        cuerpo.pack(fill="both", expand=True, **p)

        izq = ttk.LabelFrame(cuerpo, text="BIOS de la tarjeta")
        izq.grid(row=0, column=0, sticky="nsew", padx=(0, 8))
        self.lb = tk.Listbox(izq, width=34, height=12, exportselection=False, font=("Consolas", 9))
        self.lb.pack(fill="both", expand=True, padx=6, pady=6)
        self.lb.bind("<<ListboxSelect>>", lambda e: self._elegir(self.lb.curselection()[0])
                     if self.lb.curselection() else None)
        fila = ttk.Frame(izq)
        fila.pack(fill="x", padx=6, pady=(0, 6))
        ttk.Button(fila, text="Añadir otra", command=self._anadir).pack(side="left")
        self.b_quitar = ttk.Button(fila, text="Quitar", command=self._quitar)
        self.b_quitar.pack(side="left", padx=6)
        fila = ttk.Frame(izq)
        fila.pack(fill="x", padx=6, pady=(0, 6))
        ttk.Label(fila, text="Nombre:").pack(side="left")
        self.c_nombre = ttk.Combobox(fila, textvariable=self.nombre, state="readonly", width=14,
                                     values=ocm.NOMBRES[1:])
        self.c_nombre.pack(side="left", padx=6)
        self.c_nombre.bind("<<ComboboxSelected>>", lambda e: self._renombrar())
        ttk.Label(izq, text="La principal (OCM-BIOS.DAT) es la que\narranca; las otras se eligen en el MSX\n"
                  "con SDBIOS n -R (n = la cifra final).", justify="left").pack(anchor="w", padx=6, pady=(0, 6))

        der = ttk.LabelFrame(cuerpo, text="Opciones (las de make-sdb.cmd de KdL)")
        der.grid(row=0, column=1, sticky="nsew")
        fila = 0

        def titulo(texto):
            nonlocal fila
            ttk.Label(der, text=texto, font=("Segoe UI", 9, "bold")).grid(row=fila, column=0, sticky="nw", padx=6,
                                                                       pady=(6, 0))
        titulo("Tipo de máquina")
        caja = ttk.Frame(der)
        caja.grid(row=fila, column=1, sticky="w", pady=(6, 0))
        self.r_tipo = {}
        for clave, texto in ocm.TIPOS:
            self.r_tipo[clave] = ttk.Radiobutton(caja, text=texto, value=clave, variable=self.v["tipo"])
            self.r_tipo[clave].pack(anchor="w")
        fila += 1
        titulo("Disco (Disk-ROM)")
        caja = ttk.Frame(der)
        caja.grid(row=fila, column=1, sticky="w", pady=(6, 0))
        self.r_disco = {}
        for clave in ocm.DISCOS:
            self.r_disco[clave] = ttk.Radiobutton(caja, text=self.pack.texto_disco(clave), value=clave,
                                                  variable=self.v["disco"])
            self.r_disco[clave].pack(anchor="w")
            if clave not in self.pack.nucleos:
                self.r_disco[clave].state(["disabled"])
        fila += 1
        titulo("Teclado (Main-ROM)")
        caja = ttk.Frame(der)
        caja.grid(row=fila, column=1, sticky="w", pady=(6, 0))
        self.r_teclado = {}
        for clave, texto in ocm.TECLADOS:
            self.r_teclado[clave] = ttk.Radiobutton(caja, text=texto, value=clave, variable=self.v["teclado"])
            self.r_teclado[clave].pack(side="left", padx=(0, 12))
        fila += 1
        titulo("Logo (Kanji-ROM)")
        caja = ttk.Frame(der)
        caja.grid(row=fila, column=1, sticky="w", pady=(6, 0))
        self.logos = [(c, t) for c, t, _ in ocm.LOGOS if c != "propio" or self.pack.tiene_propio()]
        self.c_logo = ttk.Combobox(caja, state="readonly", width=40, values=[t for _, t in self.logos])
        self.c_logo.pack(anchor="w")
        self.c_logo.bind("<<ComboboxSelected>>", lambda e: self.v["logo"].set(self.logos[self.c_logo.current()][0]))
        marco = ttk.Frame(caja, width=400, height=152, relief="sunken")     # los PNG de KdL miden 392x146
        marco.pack(anchor="w", pady=4)
        marco.pack_propagate(False)
        self.vista = ttk.Label(marco, anchor="center")
        self.vista.pack(fill="both", expand=True)
        fila += 1
        titulo("Option-ROM")
        caja = ttk.Frame(der)
        caja.grid(row=fila, column=1, sticky="w", pady=(6, 0))
        self.ch_wifi = ttk.Checkbutton(caja, text="WiFi: BIOS del ESP8266 (detecta el módulo sola)",
                                       variable=self.v["wifi"])
        self.ch_wifi.pack(anchor="w")
        self.ch_tr = ttk.Checkbutton(caja, text="Logo del turboR", variable=self.v["logo_tr"])
        self.ch_tr.pack(anchor="w")
        fila += 1
        titulo("Extra-ROM")
        caja = ttk.Frame(der)
        caja.grid(row=fila, column=1, sticky="w", pady=(6, 6))
        self.r_extra = {}
        for clave, texto, _ in ocm.EXTRAS:
            self.r_extra[clave] = ttk.Radiobutton(caja, text=texto, value=clave, variable=self.v["extra"])
            self.r_extra[clave].pack(side="left", padx=(0, 12))
        self.resumen = ttk.Label(der, text="", foreground="#004080", wraplength=520, justify="left")
        self.resumen.grid(row=fila + 1, column=0, columnspan=2, sticky="w", padx=6, pady=(0, 6))

        pie = ttk.Frame(self.top)
        pie.pack(fill="x", **p)
        ttk.Button(pie, text="Aceptar", command=self._aceptar).pack(side="right")
        ttk.Button(pie, text="Cancelar", command=self.top.destroy).pack(side="right", padx=6)
        ttk.Button(pie, text="Por defecto", command=self._defecto).pack(side="left")

    # ------------------------------------------------------------------ lista
    def _rellenar_lista(self):
        self.lb.delete(0, "end")
        for nombre, r in self.lista:
            disco = {"nextor214": "Nextor 2", "nextor3": "Nextor 3", "megasd1": "MegaSDHC",
                     "megasd2": "MegaSDHC"}[r["disco"]] if r["tipo"] != "vacia" else ""
            self.lb.insert("end", "%-13s %-7s %s" % (nombre, ocm.NOMBRE_TIPO[r["tipo"]].split(" (")[0], disco))
        self.lb.selection_clear(0, "end")
        if self.lista:
            self.lb.selection_set(min(self.actual, len(self.lista) - 1))

    def _elegir(self, i):
        self.actual = i
        nombre, r = self.lista[i]
        self.cargando = True
        for k, var in self.v.items():
            var.set(r[k])
        self.cargando = False
        self.nombre.set(nombre)
        principal = nombre == "OCM-BIOS.DAT"
        self.c_nombre.state(["disabled"] if principal else ["!disabled", "readonly"])
        self.b_quitar.state(["disabled"] if principal else ["!disabled"])
        self.r_tipo["vacia"].state(["disabled"] if principal else ["!disabled"])
        self._ajustar()

    def _libre(self):
        usados = {n for n, _ in self.lista}
        for n in ["ALT-BIOS.DA%d" % i for i in list(range(1, 10)) + [0]]:
            if n not in usados:
                return n
        return None

    def _anadir(self):
        n = self._libre()
        if n is None:
            messagebox.showinfo("MSX SD Maker", "Ya están las diez de reserva (ALT-BIOS.DA0 a .DA9).", parent=self.top)
            return
        self.lista.append((n, ocm.receta(self.lista[self.actual][1], tipo="turbor"
                                         if self.lista[self.actual][1]["tipo"] == "msx2p" else "msx2p")))
        self.actual = len(self.lista) - 1
        self._rellenar_lista()
        self._elegir(self.actual)

    def _quitar(self):
        if self.actual == 0:
            return
        del self.lista[self.actual]
        self.actual = max(0, self.actual - 1)
        self._rellenar_lista()
        self._elegir(self.actual)

    def _renombrar(self):
        nuevo = self.nombre.get()
        if any(n == nuevo for k, (n, _) in enumerate(self.lista) if k != self.actual):
            messagebox.showwarning("MSX SD Maker", "%s ya está en la lista." % nuevo, parent=self.top)
            self.nombre.set(self.lista[self.actual][0])
            return
        self.lista[self.actual] = (nuevo, self.lista[self.actual][1])
        self._rellenar_lista()

    # ------------------------------------------------------------------ opciones
    def _cambio(self):
        if self.cargando:
            return
        self._ajustar()

    def _ajustar(self):
        """Lo que no vale en el tipo elegido se corrige y se desactiva; se guarda la receta y se pinta el logo."""
        tipo = self.v["tipo"].get()
        q = ocm.que_se_puede(tipo)
        self.cargando = True
        if q["discos"] and self.v["disco"].get() not in q["discos"]:
            self.v["disco"].set(next(d for d in q["discos"] if d in self.pack.nucleos))
        if q["teclados"] and self.v["teclado"].get() not in q["teclados"]:
            self.v["teclado"].set("bsl")
        if self.v["logo"].get() == "propio" and tipo != "msx2p":
            self.v["logo"].set("2")
        self.cargando = False
        for clave, rb in self.r_disco.items():
            rb.state(["!disabled"] if clave in q["discos"] and clave in self.pack.nucleos else ["disabled"])
        for clave, rb in self.r_teclado.items():
            rb.state(["!disabled"] if clave in q["teclados"] else ["disabled"])
        for clave, rb in self.r_extra.items():
            rb.state(["!disabled"] if q["extra"] else ["disabled"])
        self.c_logo.state(["!disabled", "readonly"] if q["logo"] else ["disabled"])
        propio = self.v["logo"].get() == "propio"
        self.ch_wifi.state(["!disabled"] if q["wifi"] and not propio else ["disabled"])
        self.ch_tr.state(["!disabled"] if q["logo_tr"] else ["disabled"])
        codigos = [c for c, _ in self.logos]
        if self.v["logo"].get() in codigos:
            self.c_logo.current(codigos.index(self.v["logo"].get()))
        r = {k: var.get() for k, var in self.v.items()}
        try:
            r = ocm.receta(r)
        except ValueError as e:
            self.resumen["text"] = str(e)
            return
        antes = self.lista[self.actual][1]
        if self.actual == 0 and antes["disco"] != r["disco"]:
            # la principal cambia de Nextor/MegaSDHC: las de reserva que llevaban el mismo la siguen
            for k, (n, otra) in enumerate(self.lista[1:], 1):
                if otra["disco"] == antes["disco"] and otra["tipo"] != "vacia":
                    try:
                        self.lista[k] = (n, ocm.receta(otra, disco=r["disco"]))
                    except ValueError:
                        pass
        self.lista[self.actual] = (self.lista[self.actual][0], r)
        self._rellenar_lista()
        texto = ocm.describir(r, self.pack)
        if propio and q["logo"]:
            texto += ". El WiFi lo decide el logo propio (opción W o X del ++Logo Toolkit)."
        if r["tipo"] == "turbor":
            texto += ". OJO: el turboR del OCM es experimental (sin R800 ni MULU)."
        if r["disco"].startswith("megasd") and r["tipo"] != "vacia":
            texto += ". MegaSDHC arranca MSX-DOS 2 (MSXDOS2.SYS), sin Nextor."
        self.resumen["text"] = texto
        self._pintar_logo(r["logo"] if q["logo"] else None, r["tipo"])

    def _pintar_logo(self, codigo, tipo):
        png = self.pack.logo_png(codigo) if codigo else None
        if png is None:
            self.imagen = None
            self.vista.configure(image="", text="sin imagen" if tipo in ("msx2p", "msx2p33") else
                                 "este tipo lleva su logo fijo" if tipo != "vacia" else "-", width=40)
            return
        try:
            self.imagen = tk.PhotoImage(data=base64.b64encode(png).decode("ascii"))
            self.vista.configure(image=self.imagen, text="", width=0)
        except tk.TclError:
            self.imagen = None
            self.vista.configure(image="", text="(no se puede mostrar la imagen)")

    # ------------------------------------------------------------------ fin
    def _defecto(self):
        sistema = "nextor3" if self.lista[0][1]["disco"] == "nextor3" else "nextor214"
        self.lista = ocm.por_defecto(sistema)
        self.actual = 0
        self._rellenar_lista()
        self._elegir(0)

    def _aceptar(self):
        try:
            ocm.comprobar_lista(self.lista)
        except ValueError as e:
            messagebox.showerror("MSX SD Maker", str(e), parent=self.top)
            return
        self.resultado = self.lista
        self.top.destroy()


def elegir(padre, pack, lista):
    """Abre el menu; devuelve la lista nueva o None si se cancela."""
    return DialogoBios(padre, pack, lista).resultado
