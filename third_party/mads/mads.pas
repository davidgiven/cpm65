(*----------------------------------------------------------------------------*)
(*  Mad-Assembler v2.1.7 by Tomasz Biela (aka Tebe/Madteam)                   *)
(*  https://github.com/tebe6502/Mad-Assembler                                 *)
(*                                                                            *)
(*  Supports 6502, WDC 65816, Sparta DOS X, virtual banks                     *)
(*  .LOCAL, .MACRO, .PROC, .STRUCT, .ARRAY, .REPT, .PAGES, .ENUM              *)
(*  #WHILE, #IF, #ELSE, #END, #CYCLE                                          *)
(*                                                                            *)
(*  last change: 2023-06-03                                                   *)
(*----------------------------------------------------------------------------*)

//  Compile using Free Pascal Compiler https://www.freepascal.org/
//  fpc -Mdelphi -vh -O3 mads.pas

// http://www.atari.org.pl/forum/viewtopic.php?id=8450
// https://forums.atariage.com/topic/179559-mads-knowledge-base/

(*----------------------------------------------------------------------------*)

program MADS;

{$I-}

uses
{$IFDEF WINDOWS}
	windows,
{$ENDIF}
	crt;

type

    t_Dirop  = (_unknown, _r=1, _or, _lo, _hi, _get, _wget, _lget, _dget, _and, _xor, _not,
		_len, _adr, _def, _filesize, _sizeof, _zpvar, _rnd, _asize, _isize,
		_fileexists, _array);

    t_Mads   = (__STACK_POINTER, __STACK_ADDRESS, __PROC_VARS_ADR);

    t_MXinst =  (REP = $c2, SEP = $e2);

    t_Attrib = (__U, __R, __W, __RW);

    _typStrREG = string [4];
    _typStrSMB = string [8];
    _typStrINT = string [32];

    _strArray  = array of string;
    _intArray  = array of integer;
    _bolArray  = array of Boolean;

    _bckAdr    = array [0..1] of integer;
    t256i      = array [0..255] of integer;
    t256c      = array [0..255] of cardinal;
    t256b      = array [0..255] of Boolean;
    t256byt    = array [0..255] of byte;
    m4kb       = array [0..4095] of byte;
    c64kb      = array [0..$FFFF] of cardinal;
    m64kb      = array [0..$FFFF] of byte;

    labels  = record
                nam: cardinal;    // identyfikator etykiety (CRC32)
                adr: cardinal;    // wartosc etykiety
                ofs: integer;     // wartosc etykiety przed zmiana adresu asemblacji
                len: integer;     // dlugosc etykiety w bajtach <1..65535>
                blk: integer;     // blok przypisany etykiecie
                lln: integer;     // dlugosc bloku .LOCAL
                lid: Boolean;     // identyfikator etykiety .LOCAL
                add: cardinal;    // jesli jest wiecej blokow o tej samej nazwie
                bnk: integer;     // licznik wirtualnych bankow przypisany do etykiety <0..$FF>, na potrzeby MADS-a jest on typu WORD
                sts: Boolean;     // czy definicja etykiety powiodla sie
                rel: Boolean;     // czy relokowac
                pas: byte;        // numer przebiegu dla danej etykiety
                typ: char;        // typ etykiety (V-ARIABLE, P-ROCEDURE, C-ONSTANT)
		lop: byte;
                use: Boolean;     // czy etykieta jest używana
                atr: t_attrib;    // atrybut __R, __W, __RW
              end;

    wywolyw = record
                 zm: string;      // wiersz listingu
                 pl: string;      // nazwa pliku ktorego zawartosc asemblujemy
                 nr: integer;     // numer linii listingu
              end;

    stosife = record
               _if_test: Boolean; // stan IF_TEST
                  _else: Boolean; // czy wystapilo .ELSE
                _okelse: integer; // numer aktualnego poziomu .IF
             old_iftest: Boolean; // stan IF_TEST przed wykonaniem nowego .IF
              end;

   relocLab = record
                adr: integer;     // adres relokowalny
                idx: integer;     // indeks do T_SMB lub T_SIZ
                blk: integer;     // numer segmentu
                blo: integer;     // numer bloku
                bnk: integer;     // bank
              end;

   segInfo =  record
               lab: string;       // etykieta segmentu
               start: integer;    // adres poczatkowy segmentu
               len: integer;      // dlugosc segmentu
               adr: integer;      // aktualny adres asemblacji segmentu
               bnk: integer;      // bank segmentu
               pas: byte;         // numer przebiegu
               atr: t_attrib;     // atrybut
              end;

   relocSmb = record
               smb: _typStrSMB;   // 8 znakowy symbol SMB dla systemu SDX
               use: Boolean;      // czy w programie nastapilo odwolanie do symbolu
	       weak: Boolean;     // czy symbol jest słaby (Weak Symbol)
              end;

   extLabel = record
               adr: cardinal;     // adres pod ktorym wystapila etykieta external
               bnk: integer;      // bank w ktorym wystapila etykieta external
               idx: integer;      // index do T_EXT
               typ: char;         // typ operacji ' ', '<', '>', '^'
               lsb: byte;
              end;

   usingLab = record
               lok: integer;      // numer obszaru lokalnego
               nam: string;       // nazwa obszaru w ktorym wystapilo .USING
               lab: string;       // etykieta
              end;

   pubTab   = record
               nam: string;       // nazwa etykiety publicznej
               typ: Boolean;      // aktualny adres asemblacji
              end;

   mesTab   = record
               pas: byte;         // numer przebiegu
	       col: byte;	  // kolor
               mes: string;       // tresc komunikatu bledu
              end;

   locTab   = record
               nam: string;       // nazwa bloku .LOCAL
               adr: integer;      // aktualny adres asemblacji
               idx: integer;      // indeks do tablicy T_LAB
               ofs: integer;      // poprzedni adres asemblacji
              end;

   arrayElm = record
               cnt: integer;      // liczba elementow
               mul: integer;      // mnoznik elementow z prawej strony
              end;

   arrayTab = record
               adr: cardinal;     // adres tablicy
               bnk: integer;      // bank przypisany tablicy
               elm: array of arrayElm; // kolejne liczby elementow tablicy [0..IDX]
               def: Boolean;      // czy zostala okreslona liczba elementow
               siz: byte;         // wielkosc pola tablicy B-YTE, W-ORD, L-ONG, D-WORD
               len: integer;      // calkowita dlugosc tablicy w bajtach
               ofs: integer;
              end;

   varTab   = record
               lok: integer;      // nr poziomu lokalnego
               nam: string;       // nazwa zmiennej
               siz: integer;      // rozmiar zmiennej
               exc: Boolean;      // exclude procedure
               cnt: integer;      // wielokrotnosc rozmiaru zmiennej
               war: cardinal;     // wartosc poczatkowa zmiennej
               adr: integer;      // adres zmiennych jesli zostal okreslony
               typ: char;         // typ zmiennej V-AR, S-TRUCT, E-NUM
               idx: integer;      // indeks do struktury tworzacej zmienna
               str: string;       // nazwa struktury tworzacej zmienna
                id: integer;      // identyfikator grupy etykiet deklarowanych przez .VAR w tym samym bloku
               zpv: Boolean;      // ZPV = TRUE dla zmiennych deklarowanych przez .ZPVAR
              end;

   stctTab  = record
                 id: integer;     // numer struktury (identyfikator)
                 no: integer;     // numer pozycji w strukturze (-1 gdy nie sa to pola struktury)
                adr: cardinal;    // adres struktury
                bnk: integer;     // bank przypisany strukturze
                idx: integer;     // index do dodatkowej struktury
                ofs: integer;     // ofset od poczatku struktury
                siz: integer;     // rozmiar danych definiowanych przez pole struktury 1..4 (B-YTE..D-WORD)
                                  // lub calkowita dlugosc danych definiowanych przez strukture
                rpt: integer;     // liczba powtorzen typu SIZ (SIZ*RPT = rozmiar calkowity pola)
                lab: string;      // etykieta wystepujaca w .STRUCT
              end;

    reptTab = record
               idx: integer;
               fln: integer;      // first line
               lln: integer;      // last line  ->  t_mac[fln..lln]
               lin: integer;      // numer linii
              end;

    procTab = record
                nam: string;      // nazwa procedury .PROC
                str: integer;     // indeks do T_MAC z nazwami parametrow
                adr: cardinal;    // adres procedury
                ofs: integer;
                bnk: integer;     // bank przypisany procedurze
                par: integer;     // liczba parametrow procedury
                ile: integer;     // liczba bajtow zajmowana przez parametry procedury
                typ: char;        // typ procedury __pDef, __pReg, __pVar
                reg: byte;        // kolejnosc rejestrow CPU
                use: Boolean;     // czy procedura zostala uzyta w programie, czy pominac ja podczas asemblacji
                len: cardinal;    // dlugosc procedury w bajtach
                pnr: integer;     // proc_nr
                prc: Boolean;     // proc = [TRUE, FALSE]
                oof: integer;     // org_ofset
                pnm: string;      // proc_name
                atr: t_attrib;    // atrybut
              end;

    pageTab = record
                adr: integer;     // poczatkowa strona pamieci
                cnt: integer;     // liczba stron pamieci
              end;

    rSizTab = record
               siz: char;
               lsb: byte;
              end;

    endTab  = record
               kod: byte;         // kod konca bloku .END??
               adr: integer;
               old: integer;
               sem: Boolean;      // czy wystapil znak {
              end;

   extName  = record
                nam: string;      // nazwa etykiety external
                siz: char;        // zadeklarowany rozmiar etykiety od 1..4 bajtow
                prc: Boolean;     // czy etykieta external jest deklaracja procedury
              end;

    heaMad  = record
               nam: string;       // nazwa etykiety
               adr: cardinal;     // adres przypisany etykiecie
               bnk: byte;         // bank przypissany etykiecie
               typ: char;         // typ etykiety (P-procedure, V-ariable, C-onstans)
               idx: integer;      // index do tablicy T_PRC gdy etykiecie external przypisano procedure
              end;

    int5    = record              // nowy typ dla OBLICZ_MNEMONIK
                 l: byte;         // liczba bajtow skladajaca sie na rozkaz CPU
                 h: t256byt;      // argumenty rozkazu
                 i: integer;      // ofset do tablic
               tmp: byte;         // bajt pomocniczy
              end;

    relVal  = record
               use: Boolean;
               cnt: integer;
              end;

    skipTab = record
               adr: integer;      // adres
               use: Boolean;      // czy zostal wywolany pseudorozkaz skoku
               cnt: byte;         // liczba odlozonych adresow w przod
              end;

    _reptArray = array of reptTab;

const

  opt_H = 1;
  opt_O = 2;
  opt_L = 4;
  opt_S = 8;
  opt_C = 16;
  opt_M = 32;
  opt_T = 64;
  opt_B = 128;


var lst, lab, hhh, mmm: textfile;
    dst: file;

    label_type: char = 'V';

    pass, status, memType, optDefault: byte;

    opt : byte = opt_H or opt_O;		// OPT default value
    atr : t_Attrib = __RW;			// ATTRIBUTE default value Read/Write
    atrDefault: t_Attrib = __U;

    asize	: byte = 8;
    isize	: byte = 8;
    longa	: byte;
    longi	: byte;

    margin	: byte = 32;

    fvalue	: byte = $ff;

    __link_stack_pointer_old, __link_stack_address_old, __link_proc_vars_adr_old: cardinal;
    __link_stack_pointer, __link_stack_address, __link_proc_vars_adr: cardinal;

    bank, blok, proc_lokal, fill, proc_idx, anonymous_idx: integer;
    whi_idx, while_nr, ora_nr, test_nr, test_idx, sym_idx, org_ofset: integer;
    hea_i, rel_ofs, wyw_idx, array_idx, buf_i, rept_cnt, skip_idx: integer;
    proc_nr, lc_nr, lokal_nr, rel_idx, smb_idx, var_id, usi_idx: integer;
    line, line_err, line_all, line_add, ___rept_ile, ext_idx, extn_idx: integer;
    pag_idx, end_idx, pub_idx, var_idx, ifelse, ds_empty: integer;

    segment	: integer = 0;
    siz_idx	: integer = 1;
    adres	: integer = -$FFFF;
    zpvar	: integer = $80;

    nul : int5;

    while_name, test_name, lst_string, lst_header, etyArray: string;
    path, name, t, global_name, proc_name, def_label: string;
    end_string, plik_h, plik_hm, plik_lst, plik_obj, warning_mes: string;
    plik_lab, plik_mac, plik_asm, macro_nr, lokal_name, warning_old: string;


    infinite    : record
                   lab, nam: string;
                   lin: integer;
                  end;

    runini      : record
                   adr: integer;
                   use: Boolean;
                  end;

    attribute   : record
                   nam: string;
                   atr: t_Attrib;
                  end;

    regOpty     : record
                   blk: Boolean;
                   use: Boolean;
                   reg: array [0..2] of integer;
                  end;

    struct      : record
                   use, drelocUSE, drelocSDX: Boolean;
                   idx, id, adres, cnt: integer;
                  end = (use: false; drelocUSE: false; drelocSDX: false; idx: 0; id: 0; adres: 0; cnt: -1);

    struct_used : record
                   use: Boolean;     // czy powstala struktura danych
                   idx: integer;     // index do struktury zalozyciela
                   cnt: integer;     // licznik pozycji struktury
                  end;

    array_used  : record
                   idx: integer;
                   max: integer;     // maksylany indeks na podstawie wprowadzonych danych
                   typ: char;
                  end;

    ext_used    : record
                   use: Boolean;
                   idx: integer;
                   siz: char;
                  end;

    dreloc      : record
                   use: Boolean;     // czy wystapila dyrektywa .RELOC
                   sdx: Boolean;     // czy wystapil pseudo rozkaz BLK SPARTA
                   siz: char;        // rozmiar etykiety
                  end;

    dlink       : record
                   use: Boolean;     // czy linkujemy blok z adresem ladowania $0000
                   stc: Boolean;     // czy sprawdzalismy adresy stosu
                   len: integer;     // dlugosc bloku linkowanego
                   emp: integer;     // dlugosc pustego bloku
                  end;

    blkupd      : record
                   adr: Boolean;     // czy wystapilo BLK UPDATE ADDRESS
                   ext: Boolean;     // czy wystapilo BLK UPDATE EXTERNAL
                   pub: Boolean;     // czy wystapilo BLK UPDATE PUBLIC
                   sym: Boolean;     // czy wystapilo BLK UPDATE SYMBOL
                   new: Boolean;     // czy wystapilo BLK UPDATE NEW SYMBOL
                  end;

    binary_file : record
                   use: Boolean;
                   adr: integer;
                  end;

    raw          : record
                    use: Boolean;
                    old: integer;
                   end;

    hea_ofs      : record
                    adr: integer;
                    old: integer;
                   end;

    enum         : record
                    use, drelocUSE, drelocSDX: Boolean;
                    val, max: integer;
                   end;



    defaultZero : Boolean = false;      // domyslnie wstawiaj zera
    xasmStyle   : Boolean = false;      // laczenie rozkazow przez ':'
    ReadEnum    : Boolean = false;      // dla odczytu etykiet @dma(narrow|dma)
    VerifyProc  : Boolean = false;
    exProcTest  : Boolean = false;      // wymagany w celu wyeliminowania 'Unreferenced procedures'
    NoAllocVar  : Boolean = false;      // wstrzymaj się z alokacją zmiennych .VAR
    code6502    : Boolean = false;
    unused_label: Boolean = false;
    regAXY_opty : Boolean = false;      // OPT R+- registry optymisation MW?,MV?
    mae_labels  : Boolean = false;      // OPT ?+- MAE ?labels
    undeclared  : Boolean = false;
    variable    : Boolean = false;
    klamra_used : Boolean = false;
    noWarning   : Boolean = false;
    lst_off     : Boolean = false;
    macro       : Boolean = false;
    labFirstCol : Boolean = false;
    test_symbols: Boolean = false;
    overflow    : Boolean = false;
    blokuj_zapis: Boolean = false;
    FOX_ripit   : Boolean = false;
    blocked     : Boolean = false;
    rel_used    : Boolean = false;
    put_used    : Boolean = false;
    exclude_proc: Boolean = false;
    mne_used    : Boolean = false;
    data_out    : Boolean = false;
    aray        : Boolean = false;
    dta_used    : Boolean = false;
    pisz        : Boolean = false;
    rept        : Boolean = false;
    rept_run    : Boolean = false;
    empty       : Boolean = false;
    reloc       : Boolean = false;
    branch      : Boolean = false;
    vector      : Boolean = false;
    silent      : Boolean = false;
    bez_lst     : Boolean = false;
    icl_used    : Boolean = false;
    komentarz   : Boolean = false;
    case_used   : Boolean = false;
    full_name   : Boolean = false;
    proc        : Boolean = false;
    run_macro   : Boolean = false;
    loop_used   : Boolean = false;
    org         : Boolean = false;
    over        : Boolean = false;
    open_ok     : Boolean = false;
    list_lab    : Boolean = false;
    list_hhh    : Boolean = false;
    list_mmm    : Boolean = false;
    list_mac    : Boolean = false;
    next_pass   : Boolean = false;
    BranchTest  : Boolean = false;

    first_lst   : Boolean = false;
    first_org   : Boolean = true;
    if_test     : Boolean = true;
    hea         : Boolean = true;

    TestWhileOpt: Boolean = true;

    skip_xsm    : Boolean = false;
    skip_use    : Boolean = false;
    skip_hlt    : Boolean = false;

    macroCmd    : Boolean = false;

    imes:      t256i;     // tablica z indeksami do komunikatow (proc INITIALIZE)
    tCRC16:    t256i;     // tablica dla kodow CRC 16           (proc INITIALIZE)
    tCRC32:    t256c;     // tablica dla kodow CRC 32           (proc INITIALIZE)


    reptPar: _strArray;   // globalna tablica dla parametrów przekazywanych do .REPT


    // zmienna przechowujaca 2 adresy wstecz
    t_bck: _bckAdr;

    // hashowane mnemoniki i tryby adresowania
    hash: m64kb;

    // bufor dla dyrektywy .GET i .PUT
    t_get: m64kb;

    // bufor dla dyrektywy .LINK
    t_lnk: m64kb;

    // bufor dla wpisywanych danych do .ARRAY
    t_tmp: c64kb;

    // bufor dla odczytu plikow przez INS, maksymalna dlugosc pliku to 64KB
    t_ins: m64kb;

    // bufor pamieci dla zapisu
    t_buf: m4kb;

    // 256 znaczników dla zmiennych odkladanych na stronie zerowej
    t_zpv: t256b;

    // T_HEA zapamieta dlugosc bloku
    t_hea: _intArray;

    // T_LIN przechowuje polaczone znakiem '\' linie listingu (rozbite na wiersze)
    t_lin: _strArray;

    // T_MAC zapamieta linie z makrami, procedurami, petlami .REPT
    t_mac: _strArray;

    // T_PAR zapamieta nazwy parametrow procedur .PROC
    t_par: _strArray;

    // T_PTH zapamieta sciezki poszukiwan dla INS i ICL
    t_pth: _strArray;

    // T_SYM zapamieta nowe symbole dla SDX (blk update new i_settd 'i_settd')
    t_sym: _strArray;

    // T_ELS zapamieta wystapienia #ELSE w blokach #IF
    t_els: _bolArray;

    // tablica przechowujaca adres naprzod
    t_skp: array of skipTab;

    // T_SEG zapamieta segmenty
    t_seg: array of segInfo;

    // T_LOC zapamieta nazwy obszarow .LOCAL
    t_loc: array of locTab;

    // MESSAGES - komunikaty o bledach i ostrzezeniach
    messages: array of mesTab;

    // T_PUB zapamieta nazwy etykiet .PUBLIC
    t_pub: array of pubTab;

    // T_VAR zapamieta nazwy etykiet .VAR
    t_var: array of varTab;

    // T_END zapamieta kolejnosci wywolywania dyrektyw .MACRO, .PROC, .LOCAL, .STRUCT, .ARRAY itd.
    t_end: array of endTab;

    // T_SIZ zapamieta rozmiary argumentow
    t_siz: array of rSizTab;

    // T_MAD zapamieta etykiety dla pliku naglowkowego *.HEA (-hm)
    t_mad: array of heaMad;

    // T_PAG zapamieta paremetry dla dyrektywy .PAGE
    t_pag: array of pageTab;

    // T_USI zapamieta paremetry dla dyrektywy .USE [.USING]
    t_usi: array of usingLab;

    // T_EXT  zapamieta adresy wystapienia etykiet external
    // T_EXTN zapamieta deklaracje etykiet external
    t_ext: array of extLabel;
    t_extn: array of extName;

    // T_ARR zapamieta parametry tablic .ARRAY
    t_arr: array of arrayTab;

    // T_REL zapamieta relokowalne adresy etykiet SDX
    t_rel: array of relocLab;

    // T_SMB zapamieta relokowalne adresy symboli SDX
    t_smb: array of relocSmb;

    // T_REP zapamieta parametry petli .REPT
    t_rep: _reptArray;

    // T_PRC zapamieta parametry procedury .PROC
    t_prc: array of procTab;

    // T_LAB zapamieta etykiety
    t_lab: array of labels;

    // T_WYW zapamieta linie z wywolywanymi makrami, pomocne przy wyswietlaniu linii z bledem
    t_wyw: array of wywolyw;

    // T_STR zapamieta nazwy struktur .STRUCT
    t_str: array of stctTab;

    // stos dla operacji .IF .ELSE .ENDIF
    if_stos: array of stosife;


    pass_end : byte = 2;       // pass = <0..2>


// komunikaty
 mes: array [0..3640] of char=(
{0}  chr(ord('V') + $80),'a','l','u','e',' ','o','u','t',' ','o','f',' ','r','a','n','g','e',
{1}  chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','E','N','D','I','F',
{2}  chr(ord('L') + $80),'a','b','e','l',' ',#9,' ','d','e','c','l','a','r','e','d',' ','t','w','i','c','e',
{3}  chr(ord('S') + $80),'t','r','i','n','g',' ','e','r','r','o','r',
{4}  chr(ord('E') + $80),'x','t','r','a',' ','c','h','a','r','a','c','t','e','r','s',' ','o','n',' ','l','i','n','e',
{5}  chr(ord('U') + $80),'n','d','e','c','l','a','r','e','d',' ','l','a','b','e','l',' ',#9,
{6}  chr(ord('N') + $80),'o',' ','m','a','t','c','h','i','n','g',' ','b','r','a','c','k','e','t',
{7}  chr(ord('N') + $80),'e','e','d',' ','p','a','r','e','n','t','h','e','s','i','s',
{8}  chr(ord('I') + $80),'l','l','e','g','a','l',' ','c','h','a','r','a','c','t','e','r',':',' ',#9,
{9}  chr(ord('R') + $80),'e','s','e','r','v','e','d',' ','w','o','r','d',' ',#9,
{10} chr(ord('N') + $80),'o',' ','O','R','G',' ','s','p','e','c','i','f','i','e','d',
{11} chr(ord('C') + $80),'P','U',' ','d','o','e','s','n','''','t',' ','h','a','v','e',' ','s','o',' ','m','a','n','y',' ','r','e','g','i','s','t','e','r','s',
{12} chr(ord('I') + $80),'l','l','e','g','a','l',' ','i','n','s','t','r','u','c','t','i','o','n',' ',
{13} chr(ord('V') + $80),'a','l','u','e',' ','o','u','t',' ','o','f',' ','r','a','n','g','e',
{14} chr(ord('I') + $80),'l','l','e','g','a','l',' ','a','d','d','r','e','s','s','i','n','g',' ','m','o','d','e',' ','(','C','P','U',' ','6','5',
{15} chr(ord('L') + $80),'a','b','e','l',' ','n','a','m','e',' ','r','e','q','u','i','r','e','d',
{16} chr(ord('I') + $80),'n','v','a','l','i','d',' ','o','p','t','i','o','n',
{17} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','E','N','D',
{18} chr(ord('C') + $80),'a','n','n','o','t',' ','o','p','e','n',' ','o','r',' ','c','r','e','a','t','e',' ','f','i','l','e',' ','''',#9,'''',
{19} chr(ord('N') + $80),'e','s','t','e','d',' ','o','p','-','c','o','d','e','s',' ','n','o','t',' ','s','u','p','p','o','r','t','e','d',
{20} chr(ord('M') + $80),'i','s','s','i','n','g',' ','''','}','''',
{21} chr(ord('B') + $80),'r','a','n','c','h',' ','o','u','t',' ','o','f',' ','r','a','n','g','e',' ','b','y',' ','$',
{22} chr(ord(' ') + $80),'b','y','t','e','s',
{23} chr(ord('U') + $80),'n','e','x','p','e','c','t','e','d',' ','e','n','d',' ','o','f',' ','l','i','n','e',
{24} chr(ord('F') + $80),'i','l','e',' ','i','s',' ','t','o','o',' ','s','h','o','r','t',
{25} chr(ord('F') + $80),'i','l','e',' ','i','s',' ','t','o','o',' ','l','o','n','g',
{26} chr(ord('D') + $80),'i','v','i','d','e',' ','b','y',' ','z','e','r','o',
{27} chr(ord('^') + $80),' ','n','o','t',' ','r','e','l','o','c','a','t','a','b','l','e',
{28} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','L','O','C','A','L',
{29} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','E','N','D','L',
{30} chr(ord('U') + $80),'s','e','r',' ','e','r','r','o','r',
{31} chr(ord('O') + $80),'p','e','r','a','n','d',' ','o','v','e','r','f','l','o','w',
{32} chr(ord('B') + $80),'a','d',' ','s','i','z','e',' ','s','p','e','c','i','f','i','e','r',
{33} chr(ord('S') + $80),'i','z','e',' ','s','p','e','c','i','f','i','e','r',' ','n','o','t',' ','r','e','q','u','i','r','e','d',
{34} chr(ord(' ') + $80),         // !!! zarezerwowane !!!  USER ERROR
{35} chr(ord('U') + $80),'n','d','e','c','l','a','r','e','d',' ','m','a','c','r','o',' ',#9,
{36} chr(ord('C') + $80),'a','n','''','t',' ','r','e','p','e','a','t',' ','t','h','i','s',' ','d','i','r','e','c','t','i','v','e',
{37} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','I','F',
{38} chr(ord('L') + $80),'a','b','e','l',' ','n','o','t',' ','r','e','q','u','i','r','e','d',
{39} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','P','R','O','C',
{40} chr(ord('I') + $80),'m','p','r','o','p','e','r',' ','n','u','m','b','e','r',' ','o','f',' ','a','c','t','u','a','l',' ','p','a','r','a','m','e','t','e','r','s',
{41} chr(ord('I') + $80),'n','c','o','m','p','a','t','i','b','l','e',' ','t','y','p','e','s',' ',#9,
{42} chr(ord('.') + $80),'E','N','D','I','F',' ','e','x','p','e','c','t','e','d',
{43} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','E','N','D','R',
{44} chr(ord('S') + $80),'M','B',' ','l','a','b','e','l',' ','t','o','o',' ','l','o','n','g',
{45} chr(ord('T') + $80),'o','o',' ','m','a','n','y',' ','b','l','o','c','k','s',
{46} chr(ord('B') + $80),'a','d',' ','p','a','r','a','m','e','t','e','r',' ','t','y','p','e',' ',#9,
{47} chr(ord('B') + $80),'a','d',' ','p','a','r','a','m','e','t','e','r',' ','n','u','m','b','e','r',
{48} chr(ord(' ') + $80),'l','i','n','e','s',' ','o','f',' ','s','o','u','r','c','e',' ','a','s','s','e','m','b','l','e','d',
{49} chr(ord(' ') + $80),'b','y','t','e','s',' ','w','r','i','t','t','e','n',' ','t','o',' ','t','h','e',' ','o','b','j','e','c','t',' ','f','i','l','e',#13,#10,
{50} chr(ord('M') + $80),'i','s','s','i','n','g',' ','t','y','p','e',' ','l','a','b','e','l',
{51} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','R','E','P','T',
{52} chr(ord('B') + $80),'a','d',' ','o','r',' ','m','i','s','s','i','n','g',' ','s','i','n','u','s',' ','p','a','r','a','m','e','t','e','r',
{53} chr(ord('O') + $80),'n','l','y',' ','R','E','L','O','C',' ','b','l','o','c','k',
{54} chr(ord('L') + $80),'a','b','e','l',' ','t','a','b','l','e',':',
{55} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','S','T','R','U','C','T',
{56} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','E','N','D','S',
{57} chr(ord('C') + $80),'a','n',' ','n','o','t',' ','u','s','e',' ','r','e','c','u','r','s','i','v','e',' ','s','t','r','u','c','t','u','r','e','s',
{58} chr(ord('I') + $80),'m','p','r','o','p','e','r',' ','s','y','n','t','a','x',
{59} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','A','R','R','A','Y',
{60} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','E','N','D','A',
{61} chr(ord('C') + $80),'P','U',' ','d','o','e','s','n','''','t',' ','h','a','v','e',' ','r','e','g','i','s','t','e','r',' ',#9,
{62} chr(ord('C') + $80),'o','n','s','t','a','n','t',' ','e','x','p','r','e','s','s','i','o','n',' ','v','i','o','l','a','t','e','s',' ','s','u','b','r','a','n','g','e',' ','b','o','u','n','d','s',
{63} chr(ord('B') + $80),'a','d',' ','r','e','g','i','s','t','e','r',' ','s','i','z','e',
{64} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','P','A','G','E','S',
{65} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','E','N','D','P','G',
{66} chr(ord('I') + $80),'n','f','i','n','i','t','e',' ','r','e','c','u','r','s','i','o','n',
{67} chr(ord('D') + $80),'e','f','a','u','l','t',' ','a','d','d','r','e','s','s','i','n','g',' ','m','o','d','e',
{68} chr(ord('U') + $80),'n','k','n','o','w','n',' ','d','i','r','e','c','t','i','v','e',' ',#9,
{69} chr(ord('U') + $80),'n','r','e','f','e','r','e','n','c','e','d',' ','p','r','o','c','e','d','u','r','e',' ',
{70} chr(ord('P') + $80),'a','g','e',' ','e','r','r','o','r',' ','a','t',' ',
{71} chr(ord('I') + $80),'l','l','e','g','a','l',' ','i','n','s','t','r','u','c','t','i','o','n',' ','a','t',' ','R','E','L','O','C',' ','b','l','o','c','k',
{72} chr(ord('U') + $80),'n','r','e','f','e','r','e','n','c','e','d',' ','d','i','r','e','c','t','i','v','e',' ','.','E','N','D',
{73} chr(ord('U') + $80),'n','d','e','f','i','n','e','d',' ','s','y','m','b','o','l',' ',#9,
{74} chr(ord('I') + $80),'n','c','o','r','r','e','c','t',' ','h','e','a','d','e','r',' ','f','o','r',' ','t','h','i','s',' ','f','i','l','e',' ','t','y','p','e',
{75} chr(ord('I') + $80),'n','c','o','m','p','a','t','i','b','l','e',' ','s','t','a','c','k',' ','p','a','r','a','m','e','t','e','r','s',
{76} chr(ord('Z') + $80),'e','r','o',' ','p','a','g','e',' ','R','E','L','O','C',' ','b','l','o','c','k',
{77} chr(ord(' ') + $80),'(','B','A','N','K','=',	// od 77 kolejnosc wystapienia istotna
{78} chr(ord(' ') + $80),'(','B','L','O','K','=',
{79} chr(ord('C') + $80),'o','u','l','d',' ','n','o','t',' ','u','s','e',' ',#9,' ','i','n',' ','t','h','i','s',' ','c','o','n','t','e','x','t',
{80} chr(ord(')') + $80),' ','E','R','R','O','R',':',' ',
{81} chr(ord('0') + $80),'2',')',
{82} chr(ord('8') + $80),'1','6',')',
{83} chr(ord('O') + $80),'R','G',' ','s','p','e','c','i','f','i','e','d',' ','a','t',' ','R','E','L','O','C',' ','b','l','o','c','k',
{84} chr(ord('C') + $80),'a','n','''','t',' ','s','k','i','p',' ','o','v','e','r',' ','t','h','i','s',
{85} chr(ord('A') + $80),'d','d','r','e','s','s',' ','r','e','l','o','c','a','t','i','o','n',' ','o','v','e','r','l','o','a','d',
{86} chr(ord('N') + $80),'o','t',' ','r','e','l','o','c','a','t','a','b','l','e',
{87} chr(ord('V') + $80),'a','r','i','a','b','l','e',' ','a','d','d','r','e','s','s',' ','o','u','t',' ','o','f',' ','r','a','n','g','e',
{88} chr(ord('M') + $80),'i','s','s','i','n','g',' ','#','W','H','I','L','E',
{89} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','E','N','D','W',
{90} chr(ord('B') + $80),'L','K',' ','U','P','D','A','T','E',' ',
{91} chr(ord('A') + $80),'D','D','R','E','S','S',
{92} chr(ord('E') + $80),'X','T','E','R','N','A','L',
{93} chr(ord('P') + $80),'U','B','L','I','C',
{94} chr(ord('S') + $80),'Y','M','B','O','L',
{95} chr(ord('M') + $80),'i','s','s','i','n','g',' ','#','I','F',
{96} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','E','N','D','T',
{97} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','M','A','C','R','O',
{98} chr(ord('S') + $80),'k','i','p','p','i','n','g',' ','o','n','l','y',' ','t','h','e',' ','f','i','r','s','t',' ','i','n','s','t','r','u','c','t','i','o','n',
{99} chr(ord('R') + $80),'e','p','e','a','t','i','n','g',' ','o','n','l','y',' ','t','h','e',' ','l','a','s','t',' ','i','n','s','t','r','u','c','t','i','o','n',
{100} chr(ord('O') + $80),'n','l','y',' ','S','D','X',' ','R','E','L','O','C',' ','b','l','o','c','k',
{101} chr(ord('L') + $80),'i','n','e',' ','t','o','o',' ','l','o','n','g',
{102} chr(ord('C') + $80),'o','n','s','t','a','n','t',' ','e','x','p','r','e','s','s','i','o','n',' ','e','x','p','e','c','t','e','d',
{103} chr(ord('C') + $80),'a','n',' ','n','o','t',' ','d','e','c','l','a','r','e',' ','l','a','b','e','l',' ',#9,' ','a','s',' ','p','u','b','l','i','c',
{104} chr(ord('S') + $80),'e','g','m','e','n','t',' ',#9,' ','e','r','r','o','r',' ','a','t',' ','$',
{105} chr(ord('W') + $80),'r','i','t','i','n','g',' ','l','i','s','t','i','n','g',' ','f','i','l','e','.','.','.',
{106} chr(ord('W') + $80),'r','i','t','i','n','g',' ','o','b','j','e','c','t',' ','f','i','l','e','.','.','.',
{107} chr(ord('U') + $80),'s','e',' ','s','q','u','a','r','e',' ','b','r','a','c','k','e','t','s',' ','i','n','s','t','e','a','d',
{108} chr(ord('C') + $80),'a','n','''','t',' ','f','i','l','l',' ','f','r','o','m',' ','h','i','g','h','e','r',' ','(','$',#9,')',' ','t','o',' ','l','o','w','e','r',' ','m','e','m','o','r','y',' ','l','o','c','a','t','i','o','n',' ','(','$',#9,')',
{109} chr(ord('A') + $80),'c','c','e','s','s',' ','v','i','o','l','a','t','i','o','n','s',' ','a','t',' ','a','d','d','r','e','s','s',' ',
{110} chr(ord('N') + $80),'o',' ','i','n','s','t','r','u','c','t','i','o','n',' ','t','o',' ','r','e','p','e','a','t',
{111} chr(ord('I') + $80),'l','l','e','g','a','l',' ','w','h','e','n',' ','A','t','a','r','i',' ','f','i','l','e',' ','h','e','a','d','e','r','s',' ','d','i','s','a','b','l','e','d',
{112} chr(ord('T') + $80),'h','e',' ','r','e','f','e','r','e','n','c','e','d',' ','l','a','b','e','l',' ',#9,' ','h','a','s',' ','n','o','t',' ','p','r','e','v','i','o','u','s','l','y',' ','b','e','e','n',' ','d','e','f','i','n','e','d',' ','p','r','o','p','e','r','l','y',
{113} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','E','N','D','S','E','G',
{114} chr(ord('U') + $80),'n','i','n','i','t','i','a','l','i','z','e','d',' ','v','a','r','i','a','b','l','e',
{115} chr(ord('U') + $80),'n','u','s','e','d',' ','l','a','b','e','l',' ',
{116} chr(ord('''') + $80),'#','''',' ','i','s',' ','a','l','l','o','w','e','d',' ','o','n','l','y',' ','i','n',' ','r','e','p','e','a','t','e','d',' ','l','i','n','e','s',
{117} chr(ord('M') + $80),'e','m','m','o','r','y',' ','s','e','g','m','e','n','t','s',' ','o','v','e','r','l','a','p',
{118} chr(ord('L') + $80),'a','b','e','l',' ',#9,' ','i','s',' ','o','n','l','y',' ','f','o','r',' ',
{119} chr(ord('I') + $80),'n','f','i','n','i','t','e',' ','l','o','o','p',' ','b','y',' ','l','a','b','e','l',' ',
{120} chr(ord('U') + $80),'n','s','t','a','b','l','e',' ','i','l','l','e','g','a','l',' ','c','o','d','e',' ',
{121} chr(ord('A') + $80),'m','b','i','g','u','o','u','s',' ','l','a','b','e','l',' ',
{122} chr(ord('M') + $80),'i','s','s','i','n','g',' ','.','E','N','D','E',
{123} chr(ord('M') + $80),'u','l','t','i','-','l','i','n','e',' ','a','r','g','u','m','e','n','t',' ','i','s',' ','n','o','t',' ','s','u','p','p','o','r','t','e','d',
{124} chr(ord('B') + $80),'u','g','g','y',' ','i','n','d','i','r','e','c','t',' ','j','u','m','p',
{125} chr(ord('B') + $80),'r','a','n','c','h',' ','t','o','o',' ','l','o','n','g',',',' ','s','o',' ','l','o','n','g',' ','b','r','a','n','c','h',' ','w','a','s',' ','u','s','e','d',' ',
{126} chr(ord('B') + $80),'r','a','n','c','h',' ','a','c','r','o','s','s',' ','p','a','g','e',' ','b','o','u','n','d','a','r','y',' ',
{127} chr(ord('R') + $80),'e','g','i','s','t','e','r',' ','A',' ','i','s',' ','c','h','a','n','g','e','d',
{128} chr(ord('M') + $80),'e','m','o','r','y',' ','r','a','n','g','e',' ','h','a','s',' ','b','e','e','n',' ','e','x','c','e','e','d','e','d',
{129} chr(ord('S') + $80),'y','n','t','a','x',':',' ','m','a','d','s',' ','s','o','u','r','c','e',' ','[','o','p','t','i','o','n','s',']',#13,#10,
      '-','b',':','a','d','d','r','e','s','s',#9,'G','e','n','e','r','a','t','e',' ','b','i','n','a','r','y',' ','f','i','l','e',' ','a','t',' ','s','p','e','c','i','f','i','e','d',' ','a','d','d','r','e','s','s',' ','<','a','d','d','r','e','s','s','>',#13,#10,
      '-','b','c',#9,#9,'A','c','t','i','v','a','t','e',' ','b','r','a','n','c','h',' ','c','o','n','d','i','t','i','o','n',' ','t','e','s','t',#13,#10,
      '-','c',#9,#9,'A','c','t','i','v','a','t','e',' ','c','a','s','e',' ','s','e','n','s','i','t','i','v','i','t','y',' ','f','o','r',' ','l','a','b','e','l','s',#13,#10,
      '-','d',':','l','a','b','e','l','=','v','a','l','u','e',#9,'D','e','f','i','n','e',' ','a',' ','l','a','b','e','l',' ','a','n','d',' ','s','e','t',' ','i','t',' ','t','o',' ','<','v','a','l','u','e','>',#13,#10,
      '-','f',#9,#9,'A','l','l','o','w',' ','m','n','e','m','o','n','i','c','s',' ','a','t',' ','t','h','e',' ','f','i','r','s','t',' ','c','o','l','u','m','n',' ','o','f',' ','a',' ','l','i','n','e',#13,#10,
      '-','f','v',':','v','a','l','u','e',#9,'S','e','t',' ','r','a','w',' ','b','i','n','a','r','y',' ','f','i','l','l',' ','b','y','t','e',' ','t','o',' ','<','v','a','l','u','e','>',#13,#10,
      '-','h','c','[',':','f','i','l','e','n','a','m','e',']',#9,'G','e','n','e','r','a','t','e',' ','"','.','h','"',' ','h','e','a','d','e','r',' ','f','i','l','e',' ','f','o','r',' ','C','A','6','5',#13,#10,
      '-','h','m','[',':','f','i','l','e','n','a','m','e',']',#9,'G','e','n','e','r','a','t','e',' ','"','.','h','e','a','"',' ','h','e','a','d','e','r',' ','f','i','l','e',' ','f','o','r',' ','M','A','D','S',#13,#10,
      '-','i',':','p','a','t','h',#9,#9,'U','s','e',' ','a','d','d','i','t','i','o','n','a','l',' ','i','n','c','l','u','d','e',' ','d','i','r','e','c','t','o','r','y',',',' ','c','a','n',' ','b','e',' ','s','p','e','c','i','f','i','e','d',' ','m','u','l','t','i','p','l','e',' ','t','i','m','e','s',#13,#10,
      '-','l','[',':','f','i','l','e','n','a','m','e',']',#9,'G','e','n','e','r','a','t','e',' ','"','.','l','s','t','"',' ','l','i','s','t','i','n','g',' ','f','i','l','e',#13,#10,
      '-','m',':','f','i','l','e','n','a','m','e',#9,'I','n','c','l','u','d','e',' ','m','a','c','r','o',' ','d','e','f','i','n','i','t','i','o','n','s',' ','f','r','o','m',' ','f','i','l','e',#13,#10,
      '-','m','l',':','v','a','l','u','e',#9,'S','e','t',' ','l','e','f','t',' ','m','a','r','g','i','n',' ','f','o','r',' ','l','i','s','t','i','n','g',' ','t','o',' ','<','v','a','l','u','e','>',#13,#10,
      '-','o',':','f','i','l','e','n','a','m','e',#9,'S','e','t',' ','o','b','j','e','c','t',' ','f','i','l','e',' ','n','a','m','e',#13,#10,
      '-','p',#9,#9,'D','i','s','p','l','a','y',' ','f','u','l','l','y',' ','q','u','a','l','i','f','i','e','d',' ','f','i','l','e',' ','n','a','m','e','s',' ','i','n',' ','l','i','s','t','i','n','g',' ','a','n','d',' ','e','r','r','o','r',' ','m','e','s','s','a','g','e','s',#13,#10,
      '-','s',#9,#9,'S','u','p','p','r','e','s','s',' ','i','n','f','o',' ','m','e','s','s','a','g','e','s',#13,#10,
      '-','t','[',':','f','i','l','e','n','a','m','e',']',#9,'G','e','n','e','r','a','t','e',' ','"','.','l','a','b','"',' ','l','a','b','e','l','s',' ','f','i','l','e',#13,#10,
      '-','u',#9,#9,'D','i','s','p','l','a','y',' ','w','a','r','n','i','n','g','s',' ','f','o','r',' ','u','n','u','s','e','d',' ','l','a','b','e','l','s',#13,#10,
      '-','v','u',#9,#9,'V','e','r','i','f','y',' ','c','o','d','e',' ','i','n','s','i','d','e',' ','u','n','r','e','f','e','r','e','n','c','e','d',' ','p','r','o','c','e','d','u','r','e','s',#13,#10,
      '-','x',#9,#9,'E','x','c','l','u','d','e',' ','u','n','r','e','f','e','r','e','n','c','e','d',' ','p','r','o','c','e','d','u','r','e','s',' ','f','r','o','m',' ','c','o','d','e',' ','g','e','n','e','r','a','t','i','o','n',
{130} chr($80),

// version

{131} chr(ord('m') + $80),'a','d','s',' ','2','.','1','.','7',chr($80),' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',' ',

     chr($80));

const

  mads_version = 131 + 1;

  TAB = ^I;            // Char for a TAB
  CR  = ^M;            // Char for a CR
  LF  = ^J;            // Char for a LF

  AllowBinaryChars     : set of char = ['0'..'1'];
  AllowDecimalChars    : set of char = ['0'..'9'];
  AllowHexChars        : set of char = ['0'..'9','A'..'F'];

  AllowDirectiveChars  : set of char = ['.','#'];

  AllowWhiteSpaces     : set of char = [' ',TAB,CR,LF];

  AllowLettersChars    : set of char = ['A'..'Z'];
  AllowMacroParamChars : set of char = ['A'..'Z','_','@'];
  AllowLabelFirstChars : set of char = ['A'..'Z','_','@','?'];
  AllowExpressionChars : set of char = ['A'..'Z','_','@','?',':'];
  AllowLineFirstChars  : set of char = ['A'..'Z','_','@','?',':','.','+','-','=','*'];

  AllowMacroChars      : set of char = ['A'..'Z','0'..'9','_','@'];
  AllowLabelChars      : set of char = ['A'..'Z','0'..'9','_','@','?','.'];

  AllowQuotes          : set of char = ['''','"'];
  AllowStringBrackets  : set of char = ['[','('];
  AllowBrackets        : set of char = ['[','(','{'];

  AllowDirectorySeparators : set of char = ['/','\'];

  AssemblyAbort : set of byte = [4,6,7,14,20,  3,8,10,12,13,15,17,18,23,24,25,28,30,34,36,40,41,46,56,57,58,62,66,73,74,76,87,104,107,122,123];

  PathDelim  = {$IFDEF MSWINDOWS} '\'; {$ELSE} '/'; {$ENDIF}

  pass_max = 20;        // maksymalna mozliwa liczba przebiegow asemblacji

  __equ    = $80;       // kody pseudo rozkazow
  __opt    = $81;
  __org    = $82;
  __ins    = $83;
  __end    = $84;
  __dta    = $85;
  __icl    = $86;
  __run    = $87;       // RUN
  __nmb    = $88;
  __ini    = $89;       // INI-RUN = 2  !!! koniecznie !!!
//  __bot    = $8a;       // BOT aktualnie nie oprogramowany
  __rmb    = $8b;
  __lmb    = $8c;
  __ert    = $8d;
//  __ift    = $8e;       // -> .IF
//  __els    = $8f;       // -> .ELSE
//  __eif    = $90;       // -> .ENDIF
//  __eli    = $91;       // -> .ELSEIF
  __smb    = $92;
  __blk    = $93;
  __ext    = $94;
  __set    = $95;

  __cpbcpd = $97;       // kody makro rozkazow __cpbcpd..__jskip
  __adbsbb = $98;
  __phrplr = $99;
  __adwsbw = $9A;
  __BckSkp = $9B;
  __inwdew = $9C;
  __addsub = $9D;
  __movaxy = $9E;
  __jskip  = $9F;       // koniec kodów makro rozkazów

  __macro  = $A0;       // kody dyrektyw, kolejnosc wg tablicy 'MAC' + $A0
  __if     = $A1;
  __endif  = $A2;
  __endm   = $A3;
  __exit   = $A4;
  __error  = $A5;
  __else   = $A6;
  __print  = $A7;       // = __echo
  __proc   = $A8;
  __endp   = $A9;
  __elseif = $AA;
  __local  = $AB;
  __endl   = $AC;
  __rept   = $AD;
  __endr   = $AE;

  __byte   = $AF;       // kody dla .BYTE, .WORD, .LONG, .DWORD
//  __word   = $B0;      // nastepuja po sobie, !!! koniecznie !!!
//  __long   = $B1;
  __dword  = $B2;

  __byteValue = __byte-1;     // zastapi operacje (...-__byte+1)

  __struct = $B3;
  __ends   = $B4;
  __ds     = $B5;
  __symbol = $B6;
  __fl     = $B7;
  __array  = $B8;
  __enda   = $B9;
  __get    = $BA;
  __put    = $BB;
  __sav    = $BC;
  __pages  = $BD;
  __endpg  = $BE;
  __reloc  = $BF;
  __dend   = $C0;	// zastepuje dyrektywy .ENDL, .ENDP, .ENDS, .ENDM, .ENDR itd.
  __link   = $C1;
  __extrn  = $C2;	// odpowiednik pseudo rozkazu EXT
  __public = $C3;	// odpowiednik dla .GLOBAL, .GLOBL

  __reg    = $C4;	// __REG, __VAR koniecznie w tej kolejnosci
  __var    = $C5;

  __or     = $C6;	// ORG
  __by     = $C7;
  __he     = $C8;
  __wo     = $C9;
  __en     = $CA;
  __sb     = $CB;

  __while  = $CC;
  __endw   = $CD;
  __test   = $CE;
  __endt   = $CF;
  __using  = $D0;
  __ifndef = $D1;
  __nowarn = $D2;
  __def    = $D3;
  __ifdef  = $D4;
  __align  = $D5;
  __zpvar  = $D6;
  __enum   = $D7;
  __ende   = $D8;
  __cb     = $D9;
  __segdef = $DA;
  __segment= $DB;
  __endseg = $DC;
  __dbyte  = $DD;
  __xget   = $DE;
  __define = $DF;
  __undef  = $E0;
  __a	   = $E1;
  __i      = $E2;
  __ai	   = $E3;
  __ia	   = $E4;
  __longa  = $E5;
  __longi  = $E6;
  __cbm    = $E7;
  __bi	   = $E8;

  __over   = __bi;	// koniec kodow dyrektyw


//  __switch = $E9;	// nie oprogramowane
//  __case   = $EA;
  __telse  = $EB;
  __cycle  = $EC;


  __blkSpa = $ED;
  __blkRel = $EE;
  __blkEmp = $EF;

  __nill   = $F0;
  __addEqu = $F1;
  __addSet = $F2;
  __xasm   = $F3;

// !!! of $F4 zaczyna się __id_
// !!! to koniec !!!

  __rel    = $0000;	// wartosc dla etykiet relokowalnych

  __relASM = $0100;	// adres asemblacji dla bloku .RELOC

  __relHea = ord('M')+ord('R') shl 8;  // naglowek 'MR' dla bloku .RELOC


                        // !!! zaczynamy koniecznie od __ID_PARAM !!!

  __id_param   = $FFF4;	// parametry procedury
  __id_mparam  = $FFF5;	// parametry makra
  __id_array   = $FFF6;
  __dta_struct = $FFF7;
  __id_ext     = $FFF8;
  __id_smb     = $FFF9;
  __id_noLab   = $FFFA;

  __id_macro   = $FFFB;	// >= __id_macro (line 6515)
  __id_define  = $FFFC;
  __id_enum    = $FFFD;
  __id_struct  = $FFFE;
  __id_proc    = $FFFF;


  __struct_run_noLabel = lo(__id_noLab);

  __array_run  = lo(__id_array);
  __macro_run  = lo(__id_macro);
  __define_run = lo(__id_define);
  __enum_run   = lo(__id_enum);
  __struct_run = lo(__id_struct);
  __proc_run   = lo(__id_proc);

  __hea_dos      = $FFFF;  // naglowek dla bloku DOS
  __hea_reloc    = $0000;  // naglowek dla bloku .RELOC
  __hea_public   = $FFED;  // naglowek dla bloku aktualizacji symboli public
  __hea_external = $FFEE;  // naglowek dla bloku aktualizacji symboli external
  __hea_address  = $FFEF;  // naglowek dla bloku aktualizacji adresow relokowalnych

  __pDef = 'D';            // Default
  __pReg = 'R';            // Registry
  __pVar = 'V';            // Variable

 __test_label  = '##TB';            // etykieta dla poczatku bloku #IF
 __telse_label = '@?@?@ML?ET';      // etykieta dla poczatku bloku #ELSE
 __endt_label  = '@?@?@ML?TE';      // etykieta dla konca bloku #IF (#END)

 __while_label = '##B';             // etykieta dla poczatku bloku #WHILE
 __endw_label  = '@?@?@ML?E';       // etykieta dla konca bloku #WHILE (#END)

 __local_name  = 'L@C?L?';          // etykieta dla .LOCAL bez nazwy

 mads_stack: array [0..2] of record
                              nam: string[14];
                              adr: cardinal;
                             end =
 (
 (nam:'@STACK_POINTER'; adr:$00fe),
 (nam:'@STACK_ADDRESS'; adr:$0500),
 (nam:'@PROC_VARS_ADR'; adr:$0600)
 );

 tType: array [1..4] of char =
 ('B','A','T','F');                 // typy uzywane wewnetrznie przez MADS

 relType: array [1..7] of char =
 ('B','W','L','D','<','>','^');     // typy zapisywane w relokowalnych plikach

 mads_param: array [1..4] of string [7] =
 ('.BYTE ', '.WORD ', '.LONG ', '.DWORD ');



function oblicz_wartosc(var a:string; var old:string): Int64; forward;
function oblicz_wartosc_noSPC(var zm,old:string; var i:integer; const sep,typ:Char): Int64; forward;
function oblicz_mnemonik(var i:integer; var a,old:string): int5; forward;

procedure search_comment_block(var i:integer; var zm,txt:string); forward;
procedure analizuj_mem(const start,koniec:integer; var old,a,old_str:string; licz:integer; const p_max:integer; const rp:Boolean); forward;
procedure analizuj_plik(var a:string; var old_str: string); forward;
procedure oblicz_dane(var i:integer; var a,old:string; const typ: byte); forward;



procedure omin_spacje (var i:integer; var a:string);
(*----------------------------------------------------------------------------*)
(*  omijamy tzw. "biale spacje" czyli spacje, tabulatory, komentarze /* */    *)
(*----------------------------------------------------------------------------*)
var txt: string;
begin

 if a<>'' then begin
  while (i<=length(a)) and (a[i] in AllowWhiteSpaces) do inc(i);

  if (i<length(a)) and ( (a[i]='/') and (a[i+1]='*') ) then begin
   txt:=''; search_comment_block(i,a, txt);

   if not(komentarz) then omin_spacje(i,a);
  end;

 end;

end;


function Tab2Space(a: string; spc: byte = 8): string;
var column, nextTabStop: integer;
    ch: char;
begin

 Result := '';
 column:=0;

 for ch in a do
  case ch of

   #9:
	begin
		nextTabStop := (column + spc) div spc * spc;
		while column <> nextTabStop do begin Result := Result + ' '; inc(column) end;
	end;

   CR, LF:
	begin
		Result := Result + ch;
		column:=0;
        end;

  else
		Result := Result + ch;
		inc(column);
  end;

end;


procedure __inc(var i:integer; var a:string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 if i>length(a) then exit;

 inc(i);
 omin_spacje(i,a);

end;


function AnsiUpperCase(a: string): string;
var i: integer;
begin

 Result:='';

 if a<>'' then
  for i := 1 to length(a) do Result:=Result+UpCase(a[i]);

end;


function UpCas_(const a: char): char;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 if not(case_used) then
  Result:=UpCase(a)
 else
  Result:=a;

end;


function ata2int(const a: byte): byte;
(*----------------------------------------------------------------------------*)
(*  zamiana znakow ATASCII na INTERNAL                                        *)
(*----------------------------------------------------------------------------*)
begin
 Result:=a;

 case (a and $7f) of
    0..31: inc(Result,64);
   32..95: dec(Result,32);
 end;

end;


function IntToStr(const a: Int64): string;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var tmp: _typStrINT;
begin
 str(a, tmp);

 Result := tmp;
end;


function StrToInt(const a: string): Int64;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var i: integer;
begin
 val(a,Result, i);
end;


procedure flush_dst;
(*----------------------------------------------------------------------------*)
(*  oproznienie bufora zapisu                                                 *)
(*----------------------------------------------------------------------------*)
begin
 if buf_i > 0 then blockwrite(dst,t_buf,buf_i);
 buf_i := 0;
end;


procedure put_dst(const a: byte);
(*----------------------------------------------------------------------------*)
(*  zapisz do bufora zapisu                                                   *)
(*----------------------------------------------------------------------------*)
var v: byte;
begin

  if fill > 0 then begin

   flush_dst;

   v := fvalue;

   while fill > 0 do begin
    blockwrite(dst, v, 1);
    dec(fill);
   end;

  end;

  t_buf[buf_i]:=a; inc(buf_i);
  if buf_i>=sizeof(t_buf) then flush_dst;
end;


function Hex(a:cardinal; b:shortint): string;
(*----------------------------------------------------------------------------*)
(*  zamiana na zapis hexadecymalny                                            *)
(*  'B' okresla maksymalna liczbe nibbli do zamiany                           *)
(*  jesli sa jeszcze jakies wartosci to kontynuuje zamiane                    *)
(*----------------------------------------------------------------------------*)
var v: byte;

const
    tHex: array [0..15] of char =
    ('0','1','2','3','4','5','6','7','8','9','A','B','C','D','E','F');

begin
 Result:='';

 while (b>0) or (a<>0) do begin

  v := byte(a);
  Result:=tHex[v shr 4] + tHex[v and $0f] + Result;

  a:=a shr 8;

  dec(b,2);
 end;

end;


function load_mes(const b: integer): string;
(*----------------------------------------------------------------------------*)
(*  tworzymy STRING z komunikatem nr w 'B'                                    *)
(*----------------------------------------------------------------------------*)
var i: integer;
begin

 i:=imes[b]-imes[b-1];

 SetLength(Result, i);
 move(mes[imes[b-1]], Result[1], i);

end;


function GetFilePath(const a: string): string;
(*----------------------------------------------------------------------------*)
(*  z pelnej nazwy pliku wycinamy sciezke (ExtractFilePath)                   *)
(*----------------------------------------------------------------------------*)
var i: integer;
begin
 Result:='';

 if a<>'' then begin
  i:=length(a);
  while (i>=1) and not(a[i]=PathDelim) do dec(i);

  Result:=a;
  SetLength(Result,i);
 end;

end;


function GetFileName(const a: string): string;
(*----------------------------------------------------------------------------*)
(*  z pelnej nazwy pliku wycinamy nazwe pliku (ExtractFileName)               *)
(*----------------------------------------------------------------------------*)
var i: integer;
begin
 Result:='';

 if a<>'' then begin
  i:=length(a);
  while (i>=1) and not(a[i]=PathDelim) do dec(i);

  Result:=copy(a,i+1,length(a));
 end;

end;


function show_full_name(const a:string; const b,c:Boolean): string;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var pth: string;
begin
 pth:=GetFilePath(a);

 Result:=a;

 if b then begin

  if pth='' then Result:=path+Result;

 end else
  Result:=GetFileName(Result);

 if c then Result:='Source: '+Result;
end;


procedure warning(const a: byte; const str_blad: string='');
(*----------------------------------------------------------------------------*)
(*  wyswietla ostrzezenie, nie przerywa asemblacji                            *)
(*----------------------------------------------------------------------------*)
var txt, nam: string;
    i, lin: integer;
begin

 if not(noWarning) then begin

  txt:=load_mes(a+1);

  lin:=line;
  nam:=global_name;

  case a of
        8: txt:=txt+'?';
      109: txt:=txt+'$'+HEX(zpvar,4);
   69,115,120,121,125,126: txt:=txt+str_blad;
       70: txt:=txt+'$'+HEX(adres,4);
      118: begin
            while pos(#9,txt)>0 do begin
             i:=pos(#9,txt);
             delete(txt, i, 1);
             insert(attribute.nam, txt, i);
             Break;
            end;

            case attribute.atr of
             __R: txt:=txt+'READ';
             __W: txt:=txt+'WRITE';
            end;
           end;
      119: begin
            txt:=txt+infinite.lab;
            lin:=infinite.lin;
            nam:=infinite.nam;
           end;
  end;

  warning_mes:=show_full_name(nam,full_name,false)+' ('+IntToStr(lin)+') WARNING: '+txt;

  if warning_mes<>warning_old then begin

   TextColor(LIGHTCYAN);

   writeln(warning_mes);
   warning_old:=warning_mes;

   NormVideo;
  end;

 end;

end;


procedure madH_save(const b:integer; const s:string);
(*----------------------------------------------------------------------------*)
(*  zapisujemy plik naglowkowy MADS'a                                         *)
(*----------------------------------------------------------------------------*)
var okej: Boolean;
    tst: char;
    i: integer;
begin

 tst:=s[1];

 okej:=false;

 for i:=High(t_mad)-1 downto 0 do
  if t_mad[i].bnk=b then
   if t_mad[i].typ=tst then begin okej:=true; Break end;

 if okej then begin
  writeln(mmm,#13#10,'; ',s);
  for i:=High(t_mad)-1 downto 0 do
   if t_mad[i].bnk=b then
    if t_mad[i].typ=tst then writeln(mmm,t_mad[i].nam,#9,'=',#9,'$',Hex(t_mad[i].adr,4));
 end;

end;


procedure new_message(var a: string; cl: byte = 0);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var i: integer;
begin

 if a='' then exit;

 a:=Tab2Space(a);

 for i := High(messages)-1 downto 0 do
  if messages[i].mes=a then begin a:=''; Exit end;

 i:=High(messages);

 messages[i].pas:=pass;
 messages[i].mes:=a;
 messages[i].col:=cl;

 SetLength(messages,i+2);

 a:='';
end;


procedure koniec(const err: byte);
(*----------------------------------------------------------------------------*)
(*  ERR = 0  bez bledow                                                       *)
(*  ERR = 1  tylko komunikaty WARNING                                         *)
(*  ERR = 2  blad i zatrzymanie asemblacji                                    *)
(*  ERR = 3  bledne parametry dla MADS'a                                      *)
(*----------------------------------------------------------------------------*)
var a, b: integer;
    ok: Boolean;
    txt: string;
begin

 if open_ok then begin

  Flush_dst;

  a:=integer( FileSize(dst) );
  CloseFile(dst);


  if list_lab then begin
   Flush(lab);
   CloseFile(lab);
  end;


  if first_lst then begin
   Flush(lst);
   CloseFile(lst);

   txt:=load_mes(105+1);                // Writing listing file...
   if not(silent) then new_message(txt, DARKGRAY);
  end;


  if (a=0) or (err>1) then
   Erase(dst)                           // usuwamy plik OBX (plik DST wczesniej musi zostac zamkniety)
  else begin
   txt:=load_mes(106+ord(raw.use)+1);
   if not(silent) then new_message(txt, DARKGRAY);
  end;


  if over then
   if end_string<>'' then write(end_string);


  if over and not(silent) then begin

   if err<>2 then begin
     txt:=IntToStr(line_all)+load_mes(48+1)+' in '+IntToStr(pass_end)+' pass';
     if pass>pass_max then txt:=txt+' (infinite loop)';

     new_message(txt, BROWN);

     if a>0 then begin
      txt:=IntToStr(a)+load_mes(49+1);
      new_message(txt, BROWN);
     end;

   end;

  end;

 end;


 if list_mmm then begin

  b:=0;
  while b<256 do begin

   ok:=false;
   for a:=High(t_mad)-1 downto 0 do
    if t_mad[a].bnk=b then begin ok:=true; Break end;

   if ok then begin

    if b>0 then writeln(mmm,#13#10,' lmb #',b,#9#9,'; BANK #',b);

    txt:='CONSTANS';   madH_save(b,txt);   // constans
    txt:='VARIABLES';  madH_save(b,txt);   // variables
    txt:='PROCEDURES'; madH_save(b,txt);   // procedures

   end;

   inc(b);
  end;

  CloseFile(mmm);
 end;

 if list_hhh then begin
  writeln(hhh,#13#10+'#endif');
  CloseFile(hhh);
 end;


 for a:=0 to High(messages)-1 do
  {if messages[a].pas < pass_max then} begin

   if messages[a].col <> 0 then TextColor(messages[a].col);

   if a>0 then
    write(#13#10,messages[a].mes)
   else
    write(messages[a].mes);

   NormVideo;

   for b:=High(messages)-1 downto 0 do    // usuwamy powtarzajace sie komunikaty
//    if messages[b].pas=messages[a].pas then
     if messages[b].mes = messages[a].mes then messages[b].pas:=$ff;

  end;

 if not(silent) and (err=2) then writeln;

 Halt(err);
end;


function TestFile(var a: string): Boolean;
(*----------------------------------------------------------------------------*)
(*  sprawdzamy istnienie pliku na dysku bez udzialu 'SysUtils',               *)
(*  jest to odpowiednik funkcji 'FileExists'                                  *)
(*----------------------------------------------------------------------------*)
var f: textfile;            // !!! koniecznie plik tekstowy !!!
begin

 AssignFile(f, a);
// {$I-}
 FileMode:=0;
 Reset(f);
// {$I+}

 if IOResult = 0 then begin
  Result:=true;
  CloseFile(f);
 end else
  Result:=false;

end;


procedure just_t(const a:cardinal);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var len: integer;

begin

 len:=length(t);

 if not(len>margin-1) then
  if len+3>margin-3 then begin
   t:=t+' +';
   while length(t)<margin do t:=t+' ';
  end else
   t:=t+' '+Hex(a,2);

end;


procedure bank_adres(a: integer);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 if (dreloc.use) and (a-rel_ofs>=0) then dec(a, rel_ofs);

 if bank>0 then t:=t+Hex(bank,2)+',';

 {if a>=0 then} t:=t+Hex(a,4);           // inaczej nie wyswietli wartosci 64bit
end;


procedure save_dst(const a: byte);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var x, y, ex, ey: integer;
    znk: char;
begin

 if (pass=pass_end) and (opt and opt_O > 0) then begin

  if org then begin

   SetLength(t,7);

   if hea and (opt and opt_H>0) and not(dreloc.sdx) then t := t + 'FFFF> ';

   x:=adres;
   y:=t_hea[hea_i];

   if dreloc.use then begin
    dec(x,rel_ofs);
    dec(y,rel_ofs);
   end;

   if hea_ofs.adr >= 0 then begin
    y:=hea_ofs.adr+(y-x); x:=hea_ofs.adr;
   end;

   if x<=y then begin
    ex:=x; ey:=y
   end else begin
    ey:=x; ex:=y
   end;

   if blok>0 then begin       // dlugosc bloku relokowalnego
    y:=y-x+1;
    znk:=',';
   end else
    znk:='-';

   if adres >= 0 then begin
    if ex>ey then bank_adres(t_hea[hea_i-1]+1) else bank_adres(x);
    if (ex<=ey) and (opt and opt_H>0) then t:=t+znk+Hex(y,4)+'>';
   end;

  // wyjatek kiedy nowy blok ma adres $FFFF - zapisujemy dodatkowo dwa bajty naglowka FF FF
   if (hea and (opt and opt_H>0) and not(dreloc.sdx)) or ({hea and} (opt and opt_H>0) and not(dreloc.sdx) and (adres = $FFFF)) then begin
    put_dst($FF); put_dst($FF);
   end;

   if (opt and opt_H > 0) then begin
    put_dst( byte(x) ); put_dst( byte(x shr 8) );
    put_dst( byte(y) ); put_dst( byte(y shr 8) );
   end;

   org:=false; hea:=false;
  end;

  just_t(a);

  if not(blokuj_zapis) then put_dst(a);

 end else begin

  fill:=0;        // istotne dla zapisu pliku RAW

  if org and raw.use then begin
   hea:=false;    // istotne dla zapisu pliku RAW
   org:=false;    // istotne dla zapisu pliku RAW
  end;

 end;

end;


procedure save_dstW(const a: integer);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 save_dst( byte(a) );         // lo
 save_dst( byte(a shr 8) );   // hi
end;


procedure save_dstS(var a: string);
(*----------------------------------------------------------------------------*)
(* zapis STRING-u, znak po znaku                                              *)
(*----------------------------------------------------------------------------*)
var i, len: integer;
begin
 len:=length(a);

 save_dstW( len );

 for i:=1 to len do save_dst( ord(a[i]) );
end;


procedure save_nul(const i: integer);
(*----------------------------------------------------------------------------*)
(* zapisuj tylko zera                                                         *)
(*----------------------------------------------------------------------------*)
var k: integer;
begin

 for k:=0 to i-1 do save_dst(0);

end;


procedure con_update(var con: string; const tmp: string);
var i: integer;
begin

 i:=pos(#9,con);

 if i>0 then begin
  delete(con, i, 1);
  insert(tmp, con, i);
 end;

end;


procedure blad(var a: string; const b: integer; str_blad: string = '');
(*----------------------------------------------------------------------------*)
(*  wyswietla komunikat bledu nr w 'B'                                        *)
(*  wyjatek stanowi b<0 wtedy wyswietli komunikat 'Branch...'                 *)
(*  dla komunikatu nr 14 wyswietli nazwe wybranego trybu pracy CPU 8-16bit    *)
(*----------------------------------------------------------------------------*)
var add, prv, con: string;
    i: integer;
begin

 if b=0 then begin

  overflow := true;

  if pass<>pass_end then exit;
 end;


 add:=''; prv:=''; con:='';

 line_err := line;

 if run_macro then begin
  con := t_wyw[1].zm;  new_message(con);
  global_name:=t_wyw[wyw_idx].pl;
  inc(line_err,t_wyw[wyw_idx].nr);

 end else
  if not(rept_run) and not(FOX_ripit) and not(loop_used) and not(code6502) then
   if line_add>0 then inc(line_err,line_add);


// usuwamy znaki #0 bo to pewnie jakies krzaki-dziwaki
 while (length(a)>0) and (pos(#0,a)>0) do SetLength(a,pos(#0,a)-1);


 if (a<>'') and not(b in [18,34]) then begin

   con := a;

   if High(t_lin) > 0 then
    for i:=1 to High(t_lin)-1 do
     con := con + '\' + t_lin[i];

   new_message(con);

 end;


 con := con+show_full_name(global_name,full_name,false)+' ('+IntToStr(Int64(line_err)+ord(line_err=0))+load_mes(81);

 if (b=0) and (str_blad<>'') then add:=add+' '+str_blad;

 if b=18 then str_blad:=a;                 // Cannont open or create file ' '

 if b in [2,5,35] then add:=add+load_mes(77+1+ord(dreloc.use))+IntToStr(bank)+')';   // BLOK / BANK

 if b=103 then add:=add+load_mes(104+1);       // ... as public

 if b=104 then add:=add+hex(adres,4);

 if b=14 then add:=load_mes( 82+ord( opt and opt_C>0 ) );    // if opt and 16>0 then add:='816)' else add:='02)';

 if b=17 then
   if proc then add:='P' else
    if macro then add:='M';

 if b<0 then
  con := con+load_mes(22)+Hex(abs(b),4)+load_mes(23)
 else
  if b<>34 then
   con := con+prv+load_mes(b+1)+add
  else
   con := con+a+add;


 if b=108 then con_update(con, hex(adres,4));

 con_update(con, str_blad);


 status := 2;

 new_message(con, LIGHTRED);

// pewne bledy wymagaja natychmiastowego zakonczenia asemblacji
// jesli wystapi za duzo bledow (>512) to też konczymy asemblacje
 if (b in AssemblyAbort) or (High(messages)>512) then begin over:=true; koniec(2) end;
end;


procedure justuj;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var j: integer;
begin

 if (pass=pass_end) and (t<>'') and not(FOX_ripit) then begin

  j:=length(t);

  while j<margin do begin
   t:=t+#9;
   inc(j,8);
  end;

 end;

end;


procedure blad_und(var old: string; const b: string; const x: byte);
(*----------------------------------------------------------------------------*)
(*  wyswietla komunikat 'Undeclared label ????'                               *)
(*  wyswietla komunikat 'Label ???? declared twice'                           *)
(*  wyswietla komunikat 'Undeclared macro ????'                               *)
(*----------------------------------------------------------------------------*)
begin

 if x=69 then
  warning(x, b)
 else
  blad(old,x, b);

end;


procedure WriteAccessFile(var a: string);
(*----------------------------------------------------------------------------*)
(*  sprawdzamy mozliwosc zapisu do pliku o podanej nazwie                     *)
(*----------------------------------------------------------------------------*)
var f: textfile;             // !!! koniecznie plik tekstowy !!!
begin

 AssignFile(f,a);
// {$I-}
 FileMode:=1;
 Rewrite(f);
// {$I+}

 if IOResult = 0 then
  CloseFile(f)
 else
  blad(a,18);

end;


procedure NormalizePath(var a: string);
var i: integer;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 if a<>'' then
  for i := 1 to length(a) do
   if a[i] in AllowDirectorySeparators then a[i]:=PathDelim;

end;


function GetFile(a: string; var zm: string): string;
(*----------------------------------------------------------------------------*)
(*  szukamy pliku w zadeklarowanych sciezkach poszukiwan                      *)
(*  PATH          sciezka z której uruchomiony jest glowny asemblowany plik   *)
(*  GLOBAL_NAME   ostatnio uzywana sciezka do operacji ICL, INS itp.          *)
(*----------------------------------------------------------------------------*)
var c, p: string;
    i: integer;
begin
 if a='' then blad(zm,3);

 NormalizePath(a);

 p:=GetFilePath(global_name)+a;

 if TestFile(p) then
  a:=p
 else begin
  p:=path+a;

  if TestFile(p) then a:=p;
 end;

 Result:=a;

 if TestFile(a) then exit;

 for i:=0 to High(t_pth)-1 do begin		// !!! kolejnosc przegladania T_PTH[0..] ma znaczenie !!!
  p:=t_pth[i];

  if p<>'' then
   if p[length(p)]<>PathDelim then p:=p+PathDelim;

  c:=p+a;
  if TestFile(c) then begin Result:=c; Break end;
 end;

end;


function l_lab(const a: string): integer;
(*----------------------------------------------------------------------------*)
(*  szukamy etykiety i zwracamy jej indeks do tablicy 'T_LAB'                 *)
(*  jesli nie ma takiej etykiety zwracamy wartosc -1                          *)
(*----------------------------------------------------------------------------*)
var x: cardinal;
    i, len: integer;
begin
 Result:=-1;

 len:=length(a);

 x:=$ffffffff;

 i:=1;
 while i<=len do begin                           // WHILE jest krótsze od FOR
  x:=tCRC32[byte(x) xor byte(a[i])] xor (x shr 8);
  inc(i);
 end;

// OK jesli znaleziona etykieta ma kod >=__id_param, lub aktualna wartosc BANK=0
// OK jesli znaleziona etykieta jest z aktualnego banku lub banku zerowego (BNK=BANK | BNK=0)

 for i:=High(t_lab)-1 downto 0 do
  if (t_lab[i].len=len) and (t_lab[i].nam=x) then
   if (bank=0) or (t_lab[i].bnk>=__id_param) then begin Result:=i; Break end else
    if t_lab[i].bnk in [bank,0] then begin Result:=i; Break end;

end;


procedure obetnij_kropke(var b: string);
(*----------------------------------------------------------------------------*)
(*  usuwamy z ciagu ostatni ciag znakow po kropce, ciag konczy znak kropki    *)
(*----------------------------------------------------------------------------*)
var i: integer;
begin

  i:=length(b);
  if (b<>'') and (i>1) then begin

   dec(i);
   while (i>=1) and (b[i]<>'.') do dec(i);

   SetLength(b,i);
  end;

end;


function load_lab(var a:string; const test:Boolean): integer;
(*----------------------------------------------------------------------------*)
(*  szukamy etykiety i zwracamy jej indeks do tablicy 'T_LAB'                 *)
(*  jesli nie ma takiej etykiety zwracamy wartosc -1                          *)
(*                                                                            *)
(*  jesli jest uruchomione makro i nie znajdziemy etykiety to szukamy w .PROC *)
(*  jesli nie znajdziemy w .PROC to wtedy szukamy w glownym programie         *)
(*                                                                            *)
(*  ostatecznie szukamy .USE [.USING]                                         *)
(*----------------------------------------------------------------------------*)
var txt: string;
    i: integer;


	function search(var x: string): integer;
	(*----------------------------------------------------------------------------*)
	(*  szukamy nazwy etykiety w tablicy T_LAB, jesli w nazwie wystepuje kropka   *)
	(*  obcinamy nazwe i szukamy dalej                                            *)
	(*----------------------------------------------------------------------------*)
	var b, t: string;
	begin

	  b:=x+lokal_name;

	  t:=b+a;
	  Result:=l_lab(t);

	  while (Result<0) and (pos('.',b)>0) do begin

		obetnij_kropke(b);

		t:=b+a;
		Result:=l_lab(t);
	  end;

	end;


begin

 Result:=-1;

 if not(ReadEnum) then begin

  if test then begin

    if run_macro then begin
     Result:=search(macro_nr);

     if Result>=0 then exit;
    end;


    if proc then begin
     Result:=search(proc_name);

     if Result>=0 then exit;
    end;

    txt:='';
    Result:=search(txt);
    if Result>=0 then exit;

  end;

  txt:=lokal_name+a;
  Result:=l_lab(txt);

  if Result<0 then Result:=search(proc_name);

 end;


  if Result<0 then
   if usi_idx>0 then                         // test dla .USE [.USING]
    for i:=0 to usi_idx-1 do
     if ((pos(t_usi[i].nam,lokal_name)=1) or (pos(t_usi[i].nam,proc_name)=1))
     or (lokal_name=t_usi[i].nam) or (proc_name=t_usi[i].nam) then begin

      txt:=t_usi[i].lab+'.'+a;

      Result:=l_lab(txt);

      if Result>=0 then
       exit
      else begin
       txt:=lokal_name+txt;

       Result:=l_lab(txt);

       if Result>=0 then exit;
      end;

     end;

end;


procedure zapisz_etykiete(const a:string; const ad:cardinal; const ba:integer; const symbol:char);
(*----------------------------------------------------------------------------*)
(*  zapisujemy nazwe etykiety, jej adres itp w pliku .LAB                     *)
(*  dodatkowo jesli jest to wymagane w pliku naglowkowym .C dla cc65          *)
(*  nie zapisujemy etykiet tymczasowych, lokalnych w makrach                  *)
(*----------------------------------------------------------------------------*)
var i: integer;
    tmp: string;
begin

 if pass=pass_end then
  if not(struct.use) and not(not(mae_labels) and (symbol='?')) and not(pos('::',a)>0) and not(pos(__local_name,a)>0) then begin

   if list_lab then writeln(lab,Hex(ba,2),#9,Hex(ad,4),#9,a);

   if not(proc) and (ba<256) then begin

    if list_hhh and (ba=0) then begin
     tmp:=a;

     while pos('.',tmp)>0 do tmp[pos('.',tmp)]:='_';

     writeln(hhh,'#define ',name,'_',tmp,' 0x',Hex(ad,4));
    end;

    if list_mmm then begin
     i:=High(t_mad);             // SAVE_MAD
                                 //
     t_mad[i].nam:=a;            //
     t_mad[i].adr:=ad;           //
     t_mad[i].bnk:=byte(ba);     //
     t_mad[i].typ:=label_type;   //
                                 //
     SetLength(t_mad,i+2);       //
    end;

   end;

  end;

end;


function loa_str(var a:string; var id:integer): integer;
(*----------------------------------------------------------------------------*)
(*  sprawdz czy wystepuje deklaracja pola struktury w T_STR                   *)
(*----------------------------------------------------------------------------*)
var i: integer;
begin

  Result:=-1;

  for i:=High(t_str)-1 downto 0 do     // !!! koniecznie przegladamy od tylu !!!
   if t_str[i].id=id then
    if t_str[i].lab=a then begin Result:=i; Break end;

// dzieki temu ze przegladamy od tylu nigdy nie trafimy na nazwe struktury,
// nazwa struktury ma numer NO ten sam co pierwsze pole struktury
end;


function loa_str_no(var id:integer; const x:integer): integer;
(*----------------------------------------------------------------------------*)
(*  odczytaj indeks do pola struktury o konkretnym numerze X                  *)
(*----------------------------------------------------------------------------*)
var i: integer;
begin

  Result:=-1;

  for i:=High(t_str)-1 downto 0 do     // !!! koniecznie przegladamy od tylu !!!
   if t_str[i].id=id then
    if t_str[i].no=x then begin Result:=i; Break end;

end;


procedure save_str(var a:string; const ofs,siz,rpt:integer; const ad:cardinal; const bn:integer);
(*----------------------------------------------------------------------------*)
(* zapisz informacje na temat pol struktury, jesli wczesniej nie wystapily    *)
(*----------------------------------------------------------------------------*)
var i: integer;
begin

  i:=loa_str(a, struct.id);

  if i<0 then begin
   i:=High(t_str);
   SetLength(t_str,i+2);
  end;

  t_str[i].id:=struct.id;

  t_str[i].no:=struct.cnt;

  t_str[i].adr := ad;
  t_str[i].bnk := bn;

  t_str[i].lab := a;
  t_str[i].ofs := ofs;
  t_str[i].siz := siz;

  if rpt=0 then
   t_str[i].rpt := 1
  else
   t_str[i].rpt := rpt;

end;


procedure s_lab(const a:string; const ad:cardinal; const ba:integer; var old:string; const symbol:char; new_local: Boolean = false);
(*----------------------------------------------------------------------------*)
(*  wlasciwa procedura realizujaca zapamietanie etykiety w tablicy 'T_LAB'    *)
(*----------------------------------------------------------------------------*)
var tmp: cardinal;
    x, len, i: integer;
begin
// sprawdz czy nie ma juz takiej etykiety
// bo jesli jest to nie dopisuj nowej pozycji tylko popraw stara
 x:=l_lab(a);

 if x<0 then begin
  x:=High(t_lab);
  SetLength(t_lab,x+2);
 end else
  if symbol<>'?' then
   if (t_lab[x].bnk<>ba) and not(struct_used.use) and not(enum.use) then blad_und(old,a,2);

 len:=length(a);

 tmp:=$ffffffff;		// CRC32

 i:=1;
 while i<=len do begin		// WHILE jest krótsze od FOR
  tmp:=tCRC32[byte(tmp) xor byte(a[i])] xor (tmp shr 8);
  inc(i);
 end;

 if pass>0 then
 if (symbol<>'?') or mae_labels then		// jesli to styl etykiet MAE to musimy je sprawdzic
  if t_lab[x].nam=tmp then			// normalnie sprawdzamy tylko etykiety z pierwszym znakiem <>'?'
   if (t_lab[x].bnk<__id_param) and not(t_lab[x].lid) then begin
{
    if t_lab[x].lid then begin

     if t_lab[x].pas=pass_end then warning(121, a)    // wieloznaczne etykiety LOCAL !!! koniecznie t_lab[x].pas

    end else begin
}
     if t_lab[x].pas=pass then blad_und(old,a,2); // nie mozna sprawdzac dwa razy tej samej etykiety w aktualnym przebiegu

     if pass < pass_max-1 then
      if not(next_pass) then			// sprawdz czy potrzebny jest dodatkowy przebieg
       if mne_used then begin			// jakis mnemonik musial zostac wczesniej wykonany

        next_pass := (t_lab[x].adr <> ad);

        if next_pass then begin

	 if (pass > 3) and (t_lab[x].lop = 0) then t_lab[x].lop:=1;	// infinite loop

//	 writeln(pass,' : ',a,',',t_lab[x].lop,' | ',t_lab[x].adr);

         infinite.lab:=a;
         infinite.lin:=line;
         infinite.nam:=global_name;
        end;

       end;

//    end;

   end;


 if (pass=pass_end) and unused_label and (ba<__id_param) and not(struct.use) and not(run_macro) and not(t_lab[x].use) then begin
   warning(115, a);
 end;


 if t_lab[x].lid and not(new_local) then blad_und(old,a,2);

 inc(t_lab[x].add);

 t_lab[x].atr := atr;

 t_lab[x].lid := new_local;

 t_lab[x].typ := label_type;

 t_lab[x].len := len;

 t_lab[x].nam := tmp;

{ if new_local then begin
  if t_lab[x].pas<>pass then t_lab[x].adr := ad;   // tylko pierwszy adres dla .LOCAL
 end else}
  t_lab[x].adr := ad;

 t_lab[x].bnk := ba;
 t_lab[x].blk := blok;

 t_lab[x].pas := pass;

 t_lab[x].ofs := org_ofset;

 if (blok>0) or dreloc.use and ({ (mae_labels = false) and} (symbol<>'?') ) then t_lab[x].rel := true;

 zapisz_etykiete(a,ad,ba,symbol);
end;


procedure save_lab(var a:string; const ad:cardinal; const ba:integer; var old:string; new_local: Boolean = false);
(*----------------------------------------------------------------------------*)
(*  zapamietujemy etykiete, adres, bank                                       *)
(*----------------------------------------------------------------------------*)
var tmp: string;
begin

 if a<>'' then begin			// !!! konieczny test

  if a='@' then begin
   a:=IntToStr(anonymous_idx)+'@';

   inc(anonymous_idx);
  end;

  if mae_labels and (a[1]<>'?') then begin

   tmp:=a;
   lokal_name:=a+'.';

  end else
   if run_macro then tmp:=macro_nr+lokal_name+a else	// !!! nie remowac LOKAL_NAME !!!
    if proc then tmp:=proc_name+lokal_name+a else
     tmp:=lokal_name+a;

  s_lab( tmp, ad, ba, old, a[1], new_local );

 end;

end;


procedure save_arr(const a:cardinal; const b:integer);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 t_arr[array_idx].adr:=a;
 t_arr[array_idx].bnk:=b;

 t_arr[array_idx].ofs:=org_ofset;

 inc(array_idx);

 if array_idx>High(t_arr) then SetLength(t_arr, array_idx+1);

end;


procedure save_hea;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 t_hea[hea_i]:=adres - 1 - fill;

 fill:=0;

 inc(hea_i);

 if hea_i>High(t_hea) then SetLength(t_hea,hea_i+1);
end;


procedure save_par(const a: string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var i: integer;
begin
 i:=High(t_par);

 t_par[i]:=a;

 SetLength(t_par,i+2);
end;


procedure save_mac(const a: string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var i: integer;
begin
 i:=High(t_mac);

 t_mac[i]:=a;

 SetLength(t_mac,i+2);
end;


procedure save_end(const a: byte);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 t_end[end_idx].kod := a;
 t_end[end_idx].adr := adres;

 t_end[end_idx].sem := false;           // semicolon {

 inc(end_idx);

 if end_idx>High(t_end) then SetLength(t_end, end_idx+1);
end;


procedure dec_end(var zm: string; const a: byte);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 dec(end_idx);

 if t_end[end_idx].kod <> a then
  case a of
   __endpg: blad(zm,64);	// Missing .PAGES
   __ends: blad(zm,55);		// Missing .STRUCT
   __endm: blad(zm,97);		// Missing .MACRO
   __endw: blad(zm,88);		// Missing .WHILE
   __endt: blad(zm,95);		// Missing .TEST
   __enda: blad(zm,59);		// Missing .ARRAY
   __endr: blad(zm,51);		// Missing .REPT
  end;

end;


procedure save_pub(var a,zm: string);
(*----------------------------------------------------------------------------*)
(*  zapisujemy symbol .PUBLIC                                                 *)
(*  jesli ADD = FALSE to w przypadku powtorzenia symbolu wystapi blad         *)
(*----------------------------------------------------------------------------*)
var i: integer;
begin

 for i:=pub_idx-1 downto 0 do           // symbole public nie moga sie powtarzac
  if t_pub[i].nam=a then blad_und(zm,a,2);

 t_pub[pub_idx].nam := a;

 inc(pub_idx);

 if pub_idx>High(t_pub) then SetLength(t_pub,pub_idx+1);
end;


procedure save_rel(var a:integer; const idx, b:integer; var reloc_value:relVal);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

if dreloc.use or dreloc.sdx then begin

  if vector then
   t_rel[rel_idx].adr:=a-rel_ofs
  else
   t_rel[rel_idx].adr:=a-rel_ofs+1;

  if not(empty) then
   t_rel[rel_idx].idx:=idx
  else
   t_rel[rel_idx].idx:=-100;

  t_rel[rel_idx].blk:=b;
  t_rel[rel_idx].blo:=blok;

  if dreloc.use then begin
   t_rel[rel_idx].idx:=siz_idx;
   t_rel[rel_idx].bnk:=bank;

   inc(siz_idx);

   rel_used:=true;               // pozwalamy na zapis rozmiaru do T_SIZ

   if siz_idx>High(t_siz) then SetLength(t_siz,siz_idx+1);
  end;

  inc(rel_idx);

  if rel_idx>High(t_rel) then SetLength(t_rel,rel_idx+1);

  reloc:=true;

  reloc_value.use:=true;

  inc(reloc_value.cnt);
 end;

end;


procedure save_relAddress(const arg:integer; var reloc_value: relVal);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

  if not(branch) then
   if t_lab[arg].rel then begin
    save_rel(adres, -1, t_lab[arg].blk, reloc_value);
   end;

end;


function wartosc(var a:string; var v:Int64; const o:char): cardinal;
(*----------------------------------------------------------------------------*)
(*  sprawdzamy zakres wartosci zmiennej 'V' na podstawie kodu w 'O'           *)
(*----------------------------------------------------------------------------*)
var x: Boolean;
    i, mx: int64;
begin
 Result:=cardinal( v );

 i:=abs(v);                  // koniecznie ABS inaczej nie zadziala prawidlowo

 case o of
               'B' : begin mx:=$ff; x := i > $FF end;
           'A','V' : begin mx:=$ffff; x := i > $FFFF end;
           'E','T' : begin mx:=$ffffff; x := i > $FFFFFF end;
//   'F','R','L','H' :  x := i > $FFFFFFFF;   // !!! nie realne !!! zaremowac aby dzialalo odejmowanie
 else
  begin mx:=$ffffffff; x:=false end;
 end;

 if x then blad(a,0, '('+IntToStr(v)+' must be between 0 and '+IntToStr(mx)+')');

end;


function _ope(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  dopuszczalne operandy                                                     *)
(*----------------------------------------------------------------------------*)
begin
 Result := (a in ['=','<','>','!'])
end;


function _eol(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  znaki konca linii                                                         *)
(*----------------------------------------------------------------------------*)
begin
 Result := (a in [#0,' ',#9])
end;


function _dec(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  dopuszczalne znaki dla liczb decymalnych                                  *)
(*----------------------------------------------------------------------------*)
begin
 Result := a in AllowDecimalChars
end;


function _mpar(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  dopuszczalne znaki dla parametrow makr                                    *)
(*----------------------------------------------------------------------------*)
begin
 Result := UpCase(a) in AllowMacroChars
end;


function _mpar_alpha(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  dopuszczalne znaki dla parametrow makr                                    *)
(*----------------------------------------------------------------------------*)
begin
 Result := UpCase(a) in AllowMacroParamChars
end;


function _alpha(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  dopuszczalne znaki alfabetu                                               *)
(*----------------------------------------------------------------------------*)
begin
 Result := UpCase(a) in AllowLettersChars
end;


function _lab(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  dopuszczalne znaki dla etykiet                                            *)
(*----------------------------------------------------------------------------*)
begin
 Result := UpCase(a) in AllowLabelChars
end;


function _bin(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  dopuszczalne znaki dla liczb binarnych                                    *)
(*----------------------------------------------------------------------------*)
begin
 Result := a in AllowBinaryChars
end;


function _hex(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  dopuszczalne znaki dla liczb heksadecymalnych                             *)
(*----------------------------------------------------------------------------*)
begin
 Result := UpCase(a) in AllowHexChars
end;


function _first_char(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  pierwsze dopuszczalne znaki dla linii                                     *)
(*----------------------------------------------------------------------------*)
begin
 Result := UpCase(a) in AllowLineFirstChars
end;


function _dir_first(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  pierwsze dopuszczalne znaki dla dyrektyw                                  *)
(*----------------------------------------------------------------------------*)
begin
 Result := a in AllowDirectiveChars
end;


function _lab_first(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  pierwsze dopuszczalne znaki dla etykiet                                   *)
(*----------------------------------------------------------------------------*)
begin
 Result := UpCase(a) in AllowLabelFirstChars
end;


function _lab_firstEx(const a: char): Boolean;
(*----------------------------------------------------------------------------*)
(*  pierwsze dopuszczalne znaki dla etykiet w wyrazeniach                     *)
(*----------------------------------------------------------------------------*)
begin
 Result := UpCase(a) in AllowExpressionChars
end;


function fASC(const a: string): byte;
(*----------------------------------------------------------------------------*)
(*  !!! koniecznie obliczamy kod dla 3 pierwszych znakow !!!                  *)
(*  obliczamy sume kontrolna dla 3 literowego ciagu znakowego 'A'..'Z'        *)
(*  obliczona suma kontrolna jest indeksem do tablicy HASH                    *)
(*----------------------------------------------------------------------------*)
var i: cardinal;
    j: integer;
begin

 Result:=0;

 if length(a)>=3 then begin          // !!! koniecznie LENGTH(A)>=3 !!! aby obliczal LDA.W itp.

  for j:=1 to 3 do
   if not(_alpha(a[j])) then exit;

  i:= ord(a[1])-ord('@') + (ord(a[2])-ord('@')) shl 5 + (ord(a[3])-ord('@')) shl 10;

  Result:=hash[i];

 end;

end;


function fCRC16(const a: string): byte;
(*----------------------------------------------------------------------------*)
(*  obliczamy sume kontrolna CRC 16-bit dla krotkiego ciagu znakowego <3..6>  *)
(*  obliczona 16-bitowa suma kontrolna jest indeksem do tablicy HASH          *)
(*----------------------------------------------------------------------------*)
var x, i: integer;
begin
 x:=$ffff;

 i:=1;
 while i<=length(a) do begin                     // WHILE jest krótsze od FOR
  x:=tCRC16[byte(x shr 8) xor byte(a[i])] xor (x shl 8);
  inc(i);
 end;

 Result:=hash[x and $ffff];
end;


function test_char(i:integer; var a:string; const sep:char = #0; const sep2:char = #0): Boolean;
(*----------------------------------------------------------------------------*)
(* test konca linii, linie moga konczyc znaki #0, #9, ' ', ';', '//','/*','\' *)
(*----------------------------------------------------------------------------*)
var txt: string;
begin

  if a='' then begin Result:=false; exit end;

  if (i<length(a)) and ( (a[i]='/') and (a[i+1]='*') ) then begin    // !!! omin_spacje !!! tutaj niemozliwe

   txt:=''; search_comment_block(i,a, txt);

{   inc(i,2);
   while i<=length(a) do begin

    if a[i]='*' then
     if a[i+1]='/' then begin

      inc(i);
      if i=length(a) then begin
       Result:=true;
       exit
      end else begin
       __inc(i,a);
       Break
      end;

     end;

    __inc(i,a);
   end;}

  end;

 Result := (a[i] in [#0,#9,'\',';',sep,sep2]) or ((a[i]='/') and (a[i+1] in ['/'{,'*'}]));
end;


procedure test_eol(const i:integer; var a,old:string; const b:char);
(*----------------------------------------------------------------------------*)
(*  sprawdzamy czy nie ma niepoprawnych znakow na koncu linii                 *)
(*  linia moze konczyc sie znakami #0,#9,';',' ','//' lub przecinkiem ','     *)
(*----------------------------------------------------------------------------*)
begin
 if not(a[i] in [#0,#9,'\',';',' ',b]) and not((a[i]='/') and (a[i+1] in ['/','*'])) then blad(old,4)
end;


function get_directive(var i:integer; const a:string; const upc: Boolean = false): string;
(*----------------------------------------------------------------------------*)
(*  pobierz dyrektywe zaczynajaca sie znakami '.', '#'                        *)
(*----------------------------------------------------------------------------*)
begin
 Result:='';

 if a<>'' then
  if _dir_first(a[i]) then begin
   Result:=a[i];
   inc(i);

   while (i<=length(a)) and _alpha(a[i]) do begin

    if upc then
     Result:=Result+UpCas_(a[i])
    else
     Result:=Result+UpCase(a[i]);

    inc(i);
   end;

  end;

end;


function get_lab(var i:integer; var a:string; const tst:Boolean): string;
(*----------------------------------------------------------------------------*)
(*  pobierz etykiete zaczynajaca sie znakami 'A'..'Z','_','?','@'             *)
(*  jesli TST = TRUE to etykieta musi zawierac jakies znaki                   *)
(*----------------------------------------------------------------------------*)
begin
 Result:='';

 if a<>'' then begin

  if tst then omin_spacje(i,a);

  if _lab_first(a[i]) then
   while _lab(a[i]) do begin Result:=Result+UpCas_(a[i]); inc(i) end;

 end;

 if tst then
  if Result='' then blad(a,15);
end;


function get_string(var i:integer; var a,old:string; const test:Boolean): string;
(*----------------------------------------------------------------------------*)
(*  pobiera ciag znakow, ograniczony znakami '' lub ""                        *)
(*  podwojny '' oznacza literalne '                                           *)
(*  podwojny "" oznacza literalne "                                           *)
(*  TEST = TRUE sprawdza czy ciag jest pusty                                  *)
(*----------------------------------------------------------------------------*)
var len: integer;
    znak, gchr: char;
begin
 Result:='';

 omin_spacje(i,a);
 if not(a[i] in AllowQuotes) then exit;

 gchr:=a[i]; len:=length(a);

 while i<=len do begin
  inc(i);         // omijamy pierwszy znak ' lub "

  znak:=a[i];

  if znak=gchr then begin
   inc(i);
   if a[i]=gchr then znak:=gchr else begin
    if test then if Result='' then blad(old,3);
    exit;
   end;
  end;

  Result:=Result+znak;
 end;

 if not(komentarz) then blad(a,3);       // nie napotkal znaku konczacego ciag ' lub "
end;


function get_datUp(var i:integer; var a:string; const sep:Char; const tst:Boolean): string;
(*----------------------------------------------------------------------------*)
(* pobieramy ciag znakow (dyrektywy), zmieniamy wielkosc liter na duze        *)
(* jeli TST = TRUE to ciag musi byc niepusty                                  *)
(*----------------------------------------------------------------------------*)
begin
 Result:='';

 omin_spacje(i,a);

 if a<>'' then
  while (a[i]<>'=') and not(test_char(i,a,' ',sep)) do begin
   Result := Result + UpCase(a[i]);
   inc(i);
  end;

 if tst then
  if Result='' then blad(a,23);

end;


function get_type(var i:integer; var zm,old: string; const tst:Boolean; err: Boolean = true): byte;
(*----------------------------------------------------------------------------*)
(*  sprawdzamy czy odczytany ciag znakow oznacza dyrektywe typu danych        *)
(*  akceptowane dyrektywy typu to .BYTE, .WORD, .LONG, .DWORD                 *)
(*----------------------------------------------------------------------------*)
var txt: string;
begin
 omin_spacje(i,zm);

// txt:=get_datUp(i,zm,#0,false);
 txt:=get_directive(i,zm);

 if (txt='') and not(tst) then begin Result:=0; exit end;   // wyjatek dla .RELOC [.BYTE] [.WORD]

 Result := fCRC16(txt);

 if err then
  if not(Result in [__byte..__dword]) then blad_und(old,txt,46);

 dec(Result, __byteValue);
end;


function get_typeExt(var i:integer; var zm:string): byte;
(*----------------------------------------------------------------------------*)
(* sprawdzamy czy odczytany ciag znakow oznacza dyrektywe typu danych dla EXT *)
(* akceptowane dyrektywy typu to .BYTE, .WORD, .LONG, .DWORD, .PROC           *)
(*----------------------------------------------------------------------------*)
var txt: string;
begin
 omin_spacje(i,zm);

// txt:=get_datUp(i,zm,'(',false);
 txt:=get_directive(i,zm);

 Result := fCRC16(txt);

 if not(Result in [__byte..__dword, __proc]) then blad_und(zm,txt,46);
end;


function ciag_ograniczony(var i:integer; var a:string; const cut:Boolean): string;
(*----------------------------------------------------------------------------*)
(*  pobiera ciag ograniczony dwoma znakami 'LEWA' i 'PRAWA'                   *)
(*  znaki 'LEWA' i 'PRAWA' moga byc zagniezdzone                              *)
(*  jesli CUT = TRUE to usuwamy poczatkowy i koncowy nawias                   *)
(*----------------------------------------------------------------------------*)
var nawias, len: integer;
    znak, lewa, prawa: char;
    petla: Boolean;
    txt: string;
begin
 Result:='';

 if not(a[i] in AllowBrackets) then exit;

 lewa:=a[i];
 if lewa='(' then prawa:=')' else prawa:=chr(ord(lewa)+2);

 nawias:=0; petla:=true; len:=length(a);

 while petla and (i<=len) do begin

  znak := a[i];

  if znak=lewa then inc(nawias) else
   if znak=prawa then dec(nawias);

//  if not(zag) then
//   if nawias>1 then test_nawias(a,lewa,0);

//  if nawias=0 then petla:=false;
  petla := not(nawias=0);

  if znak='\' then begin
   petla:=false;
   Break;
  end else

   if znak in AllowQuotes then begin

   txt:= get_string(i,a,a,false);

   Result := Result + znak + txt + znak;

   if txt = znak then Result:=Result+znak;

   end else begin
    Result := Result + UpCas_(znak);
    inc(i)
   end;

 end;


 if petla and not(komentarz) then
  case lewa of
   '[': blad(a,6);
   '(': blad(a,7);
   '{': blad(a,20);
  end;

 if cut then
  if Result<>'' then Result:=copy(Result,2,length(Result)-2);
end;


function test_macro_param(const i:integer; const a:string): Boolean;
(*----------------------------------------------------------------------------*)
(*  test na obecnosc parametrow makra, czyli :0..9, %%0..9, :label, %%label   *)
(*----------------------------------------------------------------------------*)
begin
 Result := (i<length(a)) and  ( (a[i]=':') and _mpar(a[i+1])) or ((a[i]='%') and (a[i+1]='%') and _mpar(a[i+2]) )
end;


function test_param(const i:integer; const a:string): Boolean;
(*----------------------------------------------------------------------------*)
(*  test na obecnosc parametrow makra, czyli :0..9, %%0..9                    *)
(*----------------------------------------------------------------------------*)
begin
 Result := (i<length(a)) and  ( ((a[i]=':') and _dec(a[i+1])) or ((a[i]='%') and (a[i+1]='%') and _dec(a[i+2])) )
end;


function get_dat(var i:integer; var a:string; const Sep:Char; const spacja:Boolean): string;
(*----------------------------------------------------------------------------*)
(*  wczytaj dowolne znaki, oprocz spacji, tabulatora i 'Sep'                  *)
(*  jesli wystepuja znaki otwierajace ciag, czytaj taki ciag                  *)
(*----------------------------------------------------------------------------*)
var znak: char;
    len: integer;
    txt: string;
begin
 Result:='';

 len:=length(a);

 while i<=len do

  if a[i]=Sep then
   exit
  else

  case UpCase(a[i]) of
   '[','(','{':
     if not(komentarz) then
      Result:=Result + ciag_ograniczony(i,a,false)
     else begin
      Result:=Result+a[i];
      inc(i);
     end;

   '.': Result:=Result+get_directive(i, a, true);

   'A'..'Z': Result:=Result + get_lab(i,a, false);

   '''','"':
     if not(komentarz) then begin
      znak:=a[i];

      txt:=get_string(i,a,a,false);

      Result:=Result + znak + txt + znak;

      if znak = txt then Result:=Result+znak;

     end else begin
      Result:=Result+a[i];
      inc(i);
     end;

   '/': case a[i+1] of
         '/': exit;
         '*': begin txt:=''; search_comment_block(i,a, txt); if komentarz then exit end;
        else
         begin
          Result:=Result+'/';
          inc(i);
         end;
        end;

   ';','\': exit;

   ' ',#9: if spacja then exit else begin Result:=Result+a[i]; inc(i) end;

  else
   begin
//    if a[i]=Sep then exit;
    Result := Result + UpCas_(a[i]);
    inc(i);
   end;
  end;

end;


function get_dat_noSPC(var i:integer; var a,old:string; const sep:char; const sep2:char = #0): string;
(*----------------------------------------------------------------------------*)
(*  wczytujemy ciag znakow pomijajac znaki spacji                             *)
(*----------------------------------------------------------------------------*)
var len: integer;
    txt: string;
begin
 Result:='';

 omin_spacje(i,a);

 len:=length(a);

 while i<=len do begin

  case a[i] of
   ' ',#9:
        if sep=' ' then exit else __inc(i,a);

   '.','$'{,'%'}:  // blad jesli po znakach '.', '$' jest "biały znak"
        if a[i+1] in AllowWhiteSpaces then
         exit
        else begin
         if (test_char(i+1,a,' ',#0)) and not(komentarz) then blad(old,4);
         Result:=Result+a[i]; __inc(i,a);
        end;

   '/': case a[i+1] of
         '/': exit;
         '*': begin txt:=''; search_comment_block(i,a, txt); if komentarz then exit end;
        else
         begin
          Result:=Result+'/';
          __inc(i,a);
         end;
        end;

   ';','\': exit;

  else

   if a[i] in [sep,sep2] then
    exit
   else
    Result := Result + get_dat(i,a,sep,true);

  end;

 end;

end;


function OperExt(var i:integer; var old:string; const a,b:char; var value:Boolean): char;
(*----------------------------------------------------------------------------*)
(*  operatory zlozone zamieniamy na odpowiedni jednoliterowy kod              *)
(*----------------------------------------------------------------------------*)
var x: integer;
begin
 Result:=' ';

 x:=ord(a) shl 8+ord(b);

 case x of
  15422,8509: Result := 'A';       // '<>', '!='
       15421: Result := 'B';       // '<='
       15933: Result := 'C';       // '>='
       15420: Result := 'D';       // '<<'
       15934: Result := 'E';       // '>>'
       15677: Result := '=';       // '=='
        9766: Result := 'F';       // '&&'
       31868: Result := 'G';       // '||'
 end;

 if not(value) or (Result=' ') then begin
  blad(old,8, a+b);
 end;

 inc(i,2); value:=false;
end;


function OperNew(var i:integer; var old:string; const a:char; var value:Boolean; const b:Boolean): char;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 if value<>b then blad(old,8,a);

 Result:=a;

 inc(i); value:=false;
end;


function test_string(var i:integer; var a:string; const typ:Char): integer;
(*----------------------------------------------------------------------------*)
(*  obliczamy wartosc ktora zmodyfikuje ciag znakowy lub plikowy              *)
(*  dla '*' jest to wartosc 128, czyli invers                                 *)
(*----------------------------------------------------------------------------*)
begin
 Result:=0;          // wynik jest typem ze znakiem, koniecznie !!!

 omin_spacje(i,a);

 case a[i] of
      '*': begin
            Result := 128;
            inc(i);
           end;

  '+','-': Result := integer( oblicz_wartosc_noSPC(a,a,i,',',typ) );
 end;

 omin_spacje(i,a);
end;


procedure subrange_bounds(var a:string; const v,y:integer);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
  if (v<0) or (v>y) then blad(a,62);
end;


procedure save_dta(const war:cardinal; var tmp:string; const op_:char; const invers:byte);
(*----------------------------------------------------------------------------*)
(*  zapisujemy bajty danych do .ARRAY w zaleznosci od ustawionego typu danych *)
(*----------------------------------------------------------------------------*)
var k, i: integer;
    v: byte;
begin

 if aray or put_used then
  if array_used.idx>$FFFF then exit else begin

   if op_ in ['C','D'] then begin
    i:=length(tmp);

    for k:=1 to i do begin
     v:=byte( ord(tmp[k])+invers );
     if op_='D' then v:=ata2int(v);

     {if not(loop_used) and not(FOX_ripit) then} just_t(v);

     if aray then
      t_tmp[array_used.idx]:=v
     else
      t_get[array_used.idx]:=v;

     inc(array_used.idx);

     if array_used.idx>array_used.max then array_used.max:=array_used.idx;
    end;

    exit;
   end;

   {if not(loop_used) and not(FOX_ripit) then} just_t(war);

   if aray then
    t_tmp[array_used.idx]:=cardinal(war)
   else
    t_get[array_used.idx]:=byte(war);

   inc(array_used.idx);

   if array_used.idx>array_used.max then array_used.max:=array_used.idx;

   exit;
  end;


  case op_ of
    'L','B':
         begin
          save_dst( byte(war) );            inc(adres);
         end;

    'H': begin
          save_dst( byte(war shr 8) );      inc(adres);
         end;

    'M': begin
          save_dst( byte(war shr 16) );     inc(adres);
         end;

    'G': begin
          save_dst( byte(war shr 24) );     inc(adres);
         end;

    'A','V':
         begin
          save_dst( byte(war) );
          save_dst( byte(war shr 8) );      inc(adres,2);
         end;

    'T','E':
         begin
          save_dst( byte(war) );
          save_dst( byte(war shr 8) );
          save_dst( byte(war shr 16) );     inc(adres,3);
         end;

    'F': begin
          save_dst( byte(war) );
          save_dst( byte(war shr 8) );
          save_dst( byte(war shr 16) );
          save_dst( byte(war shr 24) );     inc(adres,4);
         end;

    'R': begin
          save_dst( byte(war shr 24) );
          save_dst( byte(war shr 16) );
          save_dst( byte(war shr 8) );
          save_dst( byte(war) );            inc(adres,4);
         end;

    'C','D':
         begin
          i:=length(tmp);

          for k:=1 to i do begin
           v:=ord(tmp[k]);

           if op_='D' then v:=ata2int(v);

           inc(v, invers);

           save_dst(v);
          end;
                                            inc(adres,i);
         end;

   end;

end;


function oblicz_wartosc_ogr(var zm,old:string; var i:integer): Int64;
(*----------------------------------------------------------------------------*)
(*  obliczamy wartosc ograniczona nawiasami '[' lub '('                       *)
(*----------------------------------------------------------------------------*)
var txt: string;
    k: integer;
begin
 Result:=0;

 omin_spacje(i,zm);

 if zm[i] in AllowStringBrackets then begin
  txt:=ciag_ograniczony(i,zm,true);

  k:=1;
  Result:=oblicz_wartosc_noSPC(txt,old,k,#0,'F')
 end;

end;


function get_labelEx(var i:integer; var a:string): string;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var ch: char;
    txt: string;
begin
 Result:='';

 if a[i] in AllowQuotes then begin
  ch:=a[i];

  txt:=get_string(i,a,a,true);

  Result:=ch + txt + ch;

  if txt=ch then Result:=Result+ch;
 end else

 if _lab_firstEx(a[i]) then begin

  Result:=Result+UpCas_(a[i]);
  inc(i);

  while _lab(a[i]) do begin Result:=Result+UpCas_(a[i]); inc(i) end;

 end;

 //if not( _eol(a[i]) ) then blad(old,8,a[i]);   // z tym testem nie policzy ciagu  wyr|wyr
end;


function get_labEx(var i:integer; var a,old:string): string;
(*----------------------------------------------------------------------------*)
(*  pobierz etykiete zaczynajaca sie znakami 'A'..'Z','_','?','@',':'         *)
(*  jesli wystepuja nawiasy '( )' lub '[ ]' to usuwamy je                     *)
(*----------------------------------------------------------------------------*)
var tmp: string;
    k: integer;
begin

 omin_spacje(i,a);

 if a[i] in AllowStringBrackets then begin
  tmp := ciag_ograniczony(i,a,true);

  k:=1;
  omin_spacje(k,tmp);

  Result := get_labelEx(k, tmp);
 end else
  Result := get_labelEx(i, a);

 if Result='' then blad(old,15);

end;


function load_label_ofset(a:string; var old:string; const test:Boolean): integer;
(*----------------------------------------------------------------------------*)
(*  znajdujemy indeks do tablicy T_LAB                                        *)
(*----------------------------------------------------------------------------*)
var b: integer;
begin

 if a='' then blad(old,23);

 if a[1]=':' then begin
  b     := bank;
  bank  := 0;         // wymuszamy BANK=0 aby odczytac etykiete z najnizszego poziomu

  a:=copy(a,2,length(a));
  Result:=l_lab(a);

  bank  := b;         // przywracamy poprzednia wartosc BANK
 end else
  Result:=load_lab(a,true);

 if test then
  if (Result<0) and (pass=pass_end) then blad_und(old,a,5);

end;


procedure testRange(var old:string; var i:integer; const b:byte);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 if (i<0) or (i>$FFFF) then begin
  blad(old,b);
  i:=0;
 end;

end;


function read_DEC(var i:integer; var a: string): string;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 Result:='';

 while (i<=length(a)) and _dec(a[i]) do begin Result:=Result+a[i]; inc(i) {__inc(i,a)} end;

end;


function read_HEX(var i:integer; var a,old: string): string;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 inc(i);                                               // omin pierwszy znak '$'

 Result:='';
 while (i<=length(a)) and _hex(a[i]) do begin Result:=Result+UpCase(a[i]); inc(i) end;

 if not(test_param(i,a)) then
  if Result='' then blad(old,8,a[i]);

 Result:='$'+Result;
end;


function macro_rept_if_test: Boolean;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 Result := (not(rept) and if_test)
end;


procedure save_lst(const c:char);
(*----------------------------------------------------------------------------*)
(*  formatowanie wierszy listingu przed zapisaniem ich do pliku .LST          *)
(*----------------------------------------------------------------------------*)
var i: byte;
begin

// if pass=pass_end then begin        // !!! nie zadziala dla OPT F+ gdy uzyjemy .DS XXX
                                      // !!! musi uzyc SAVE_DST aby "wyplul" FILL

  if not(loop_used) and not(FOX_ripit) then begin
   t:=IntToStr(line);
   while length(t)<6 do t:=' '+t;
   t:=t+' ';
  end;


  case c of

   'l': if not(FOX_ripit) then begin t:=t+'= '; bank_adres(nul.i) end;

   'i': bank_adres(adres);

   'a': begin

          if not(hea) and not(loop_used) and not(FOX_ripit) and
             not(struct.use) and (adres>=0) then bank_adres(adres);

          if nul.l>0 then begin
           data_out:=true;
           for i:=0 to nul.l-1 do save_dst(nul.h[i]);
          end;

        end;

  end;   // end case

// end;

 inc(adres,nul.l);    // to zawsze musi sie wykonac niezaleznie od przebiegu

end;


procedure zapisz_lokal;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 t_loc[lokal_nr].nam := lokal_name;

 inc(lokal_nr);

 if lokal_nr>High(t_loc) then SetLength(t_loc,lokal_nr+1);
end;


procedure oddaj_lokal(var a: string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 if lokal_nr=0 then blad(a,28);
 dec(lokal_nr);

 lokal_name := t_loc[lokal_nr].nam;
end;


procedure new_DOS_header;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var old_opt: byte;
begin
 old_opt:=opt;

 opt:=opt or opt_H;               // wymuszamy zapis naglowka DOS-a
 save_hea;

 org:=true;

 opt:=old_opt;
end;


function read_elements(var i: integer; var zm: string; const idx: integer; const mode: Boolean): integer;
(*----------------------------------------------------------------------------*)
(* mode (true)  odczyt liczby elementow                                       *)
(* mode (false) sprawdzenie zakresu dla liczby elementow                      *)
(*----------------------------------------------------------------------------*)
var txt: string;
    ofset, k, cnt: integer;
begin

   Result:=0;

   cnt:=0;

   omin_spacje(i,zm);

   while not test_char(i, zm, '.',':') do begin      // odczyt liczby elementow [] [] [] ...

           if zm[i]='[' then
            txt:=ciag_ograniczony(i,zm,false)
           else
            Break;

           ofset:= integer( oblicz_wartosc(txt, zm) );

           if mode then begin                        // zapisanie liczby elementow tablicy
             k:=High(t_arr[idx].elm);

             t_arr[idx].elm[k].cnt:=ofset;

             SetLength(t_arr[idx].elm, k+2);
           end else begin                            // sprawdzenie liczby elementow, obliczenie adresu

             subrange_bounds(zm,ofset,t_arr[idx].elm[cnt].cnt-1);

             Result := Result + ofset * t_arr[idx].elm[cnt].mul;

           end;

           inc(cnt);
           omin_spacje(i,zm);
   end;

end;


procedure put_lst(const a:string);
(*----------------------------------------------------------------------------*)
(*  zapisujemy wiersze listingu po asemblacji do pliku .LST                   *)
(*----------------------------------------------------------------------------*)
begin

 if (pass=pass_end) and (a<>'') then begin

   if run_macro then           // nie zapisuj zawartosci makra jesli bit5 OPT skasowany
    if (opt and opt_M=0) and not(data_out) then exit;

   if (opt and opt_L>0) and not(FOX_ripit) then begin

    if not(first_lst) then begin
     WriteAccessFile(plik_lst); AssignFile(lst,plik_lst); FileMode:=1; Rewrite(lst);
     first_lst:=true;
    end;

    if lst_header<>'' then begin
     writeln(lst, lst_header);
     lst_header:='';
    end;

    if lst_string<>'' then begin
     writeln(lst, lst_string);
     lst_string:='';
    end;

    writeln(lst,a);

   end;

   if (opt and opt_S>0) and not(FOX_ripit) then writeln(a);

   if not(FOX_ripit) then t:='';

 end;

end;


procedure wymus_zapis_lst(var a: string);
(*----------------------------------------------------------------------------*)
(*  dodatkowe wymuszenie zapisania wiersza listingu do pliku .LST             *)
(*----------------------------------------------------------------------------*)
begin

 if pass=pass_end then begin
  save_lst(' ');
  justuj;  put_lst(t+a);
 end;

end;


procedure zapisz_lst(var a: string);
(*----------------------------------------------------------------------------*)
(*  wymuszenie zapisania wiersza listingu do pliku .LST                       *)
(*----------------------------------------------------------------------------*)
begin

 if (pass=pass_end) then begin
  justuj;  put_lst(t+a);  a:='';
 end;

end;


procedure get_array(var i: integer; var zm, ety: string; a: integer);
var k, idx, _odd: integer;
    r: byte;
begin
          save_lab(ety, array_idx, __id_array, zm);
          save_lst('i');


          save_arr(a, bank);                            // tutaj ARRAY_IDX zostaje zwiekszone o 1

          omin_spacje(i,zm);                            // od tego momentu uzywamy ARRAY_IDX-1

          SetLength(t_arr[array_idx-1].elm, 1);         // tablica z kolejnymi liczbami elementow tablicy

          read_elements(i,zm, array_idx-1, true);       // ustalenie liczby elementow tablicy

          array_used.max:=0;

          r:=get_type(i,zm,zm, false);
          if r=0 then r:=1;                             // domyslny typ .BYTE

          t_arr[array_idx-1].siz := r;                  // typ danych .BYTE, .WORD etc.


          if High(t_arr[array_idx-1].elm)=0 then begin  // brak rozmiaru tablicy
           idx:=$FFFF;
           t_arr[array_idx-1].elm[0].cnt:=idx div r;

           t_arr[array_idx-1].elm[0].mul:=r;

           t_arr[array_idx-1].def:=false;
          end else                                      // okreslony rozmiar tablicy
           t_arr[array_idx-1].def:=true;


          _odd := t_arr[array_idx-1].elm[0].cnt;        // pierwsza liczba elementow

          for k := 1 to High(t_arr[array_idx-1].elm)-1 do
           _odd := _odd * t_arr[array_idx-1].elm[k].cnt;

          t_arr[array_idx-1].len := _odd * r;          // calkowita dlugosc w bajtach


          _odd:=1;                                     // mnoznik dla kolejnych kolumn
          for k := High(t_arr[array_idx-1].elm)-1 downto 0 do begin
           t_arr[array_idx-1].elm[k].mul := _odd * r;

           _odd := _odd * t_arr[array_idx-1].elm[k].cnt;
          end;


          if t_arr[array_idx-1].len>$FFFF then blad(zm,62);

          array_used.typ := tType[ t_arr[array_idx-1].siz ];
end;


procedure save_dtaS(war:string; ile:integer; const typ: byte; var old: string);
(*----------------------------------------------------------------------------*)
(* zapisanie wartosci danych tworzonych przez strukture                       *)
(* w celu zachowania relokowalnosci zapis przez OBLICZ_DANE                   *)
(*----------------------------------------------------------------------------*)
var i: integer;
begin

 while ile>0 do begin

  i:=1;
  oblicz_dane(i, war, old, typ);

  war:='0';                       // jesli wystapil :rept to generuj zera  (np. label :cnt .word)

  dec(ile);
 end;

end;


procedure __next(var i:integer; var zm:string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 omin_spacje(i,zm);
 if zm[i]=',' then __inc(i,zm);
 omin_spacje(i,zm);
end;


procedure get_parameters(var j:integer; var str:string; var par:_strArray; const mae:Boolean; const sep1:char = '.'; const sep2:char = ':');
(*----------------------------------------------------------------------------*)
(*  jesli wystepuje znak '=' to omijamy spacje sprzed i zza znaku '='         *)
(*  zapamietamy wszystkie etykiety (parametry) w tablicy dynamicznej          *)
(*----------------------------------------------------------------------------*)
var txt: string;
    i: integer;
begin

    SetLength(par,1);

    if str='' then exit;

    omin_spacje(j,str);

    while not(test_char(j,str, sep1,sep2)) do begin

      txt:=get_dat(j,str,',',true);   // TRUE - konczy gdy napotka biala spacje

      i:=length(txt);                 // wyjatek jesli odczytal ciag znakow zakonczony
                                      // znakiem '=', np. 'label='
      if i>0 then
       if txt[i]='=' then begin
        SetLength(txt, i-1);
        dec(j);
       end;


      i := j;

      omin_spacje(j,str);

      if str[j]='=' then begin        // '=' nowa wartosc dla etykiety
       __inc(j,str);
       txt:=txt+'=';
       txt:=txt+get_dat(j,str,',',true);
      end else
       j := i;                        // jesli nie odczytal znaku '='


   //   if txt<>'' then begin        // !!! inaczej nie bedzie pomijal parametrow PROC !!!
                                     // np. proc_label ,1
       i:=High(par);

       par[i]:=txt;

       SetLength(par,i+2);

  //    end;


      if str[j] in [',',' ',#9] then
       __next(j,str)
      else
       if mae and test_char(j,str) then Break;

    end;

end;


procedure get_define_param(var k: integer; var a, txt: string; num: integer);
var j, t: integer;
    par: _strArray;
    tmp: string;
begin

 omin_spacje(k, a);

 if a[k] in AllowStringBrackets then begin
    tmp:=ciag_ograniczony(k,a,true);

    t:=1;
    get_parameters(t,tmp,par,false);

    for t := 0 to High(par) do
     if t=0 then begin

       while pos('%%0', txt) > 0 do begin
        j := pos('%%0', txt);
        delete(txt, j, 3);
        insert(IntToStr(High(par)), txt, j);
       end;

       while pos(':0', txt) > 0 do begin
        j := pos(':0', txt);
        delete(txt, j, 2);
        insert(IntToStr(High(par)), txt, j);
       end;

     end else begin

       while pos('%%'+IntToStr(t), txt) > 0 do begin
        j := pos('%%'+IntToStr(t), txt);
        delete(txt, j, 3);
        insert(par[t-1], txt, j);
       end;

       while pos(':'+IntToStr(t), txt) > 0 do begin
        j := pos(':'+IntToStr(t), txt);
        delete(txt, j, 2);
        insert(par[t-1], txt, j);
       end;

     end;

     if num <> High(par) then blad(a, 40);

 end else
  blad(a, 7);

end;


function get_define(var i: integer; arg: integer; var a: string): string;
var k: integer;
    txt: string;
begin

 k:=i;

 txt := t_mac[t_lab[arg].adr+2];

 if t_mac[t_lab[arg].adr+1] <> '' then begin

   get_define_param(k, a, txt, StrToInt(t_mac[t_lab[arg].adr+1]));

   delete(a, i, k-i);

 end;

 Result := txt;

end;


function oblicz_wartosc(var a:string; var old:string): Int64;
(*----------------------------------------------------------------------------*)
(*  obliczamy wartosc wyrazenia, uwzgledniajac operacje arytmetyczne          *)
(*  w 'J' jest licznik dla STOS'u                                             *)
(*  zamiast tablic dynamicznych wprowadzilem tablice statyczne i ograniczylem *)
(*  maksymalna liczbe operacji i operatorow w wyrazeniu do 512                *)
(*----------------------------------------------------------------------------*)
type znak_wart = record
                  znak: char;
                  wart: Int64;
                 end;

     _typCash  = array [0..16] of char;  // taka sama liczba elementow jak PRIOR
     _typOper  = array [0..511] of char;
     _typStos  = array [0..511] of znak_wart;


var i, j, b, x, k, v, pomoc, ofset, _hlp, len, op_idx, arg: integer;
    old_reloc_value_cnt: integer;
    tmp, txt: string;
    iarg, war: Int64;
    petla, value, old_reloc_value_use: Boolean;
    oper, byt: char;

    fsize: file;

    reloc_value: relVal;

    stos_: _strArray;
    cash : _typCash;
    stos : _typStos;
    op   : _typOper;

    label LOOP;

const
 prior: array [0..16] of char=          // piorytet operatorow
 ('D','E','&','|','^','/','*','%','+',{'-',}'=','A','B','<','C','>','F','G');

begin

 if a='' then blad(old,23);

LOOP:

 Result:=0;

 // init tablicy dynamicznej OP
// SetLength(op,2);
 op[0]:='+'; oper:='+'; op_idx:=1;

 i:=1; war:=0; b:=0;

// fillchar(cash,sizeof(cash),' ');   // wypelniamy spacjami

 cash[0]:=' ';
 cash[1]:=' ';
 cash[2]:=' ';
 cash[3]:=' ';
 cash[4]:=' ';
 cash[5]:=' ';
 cash[6]:=' ';
 cash[7]:=' ';
 cash[8]:=' ';
 cash[9]:=' ';
 cash[10]:=' ';
 cash[11]:=' ';
 cash[12]:=' ';
 cash[13]:=' ';
 cash[14]:=' ';
 cash[15]:=' ';
 cash[16]:=' ';

 value:=false;

 reloc_value.use:=false;
 reloc_value.cnt:=0;

 j:=1;               // na pozycji zerowej (J=0) tablicy 'STOS' dopiszemy '+0'
                     // !!! zmienne I,J uzywane sa przez petle WHILE !!!

// SetLength(stos,3);

 len:=length(a);

 while (i<=len) and not(overflow) do begin

  case UpCase(a[i]) of

   '#': begin
         if ___rept_ile<0 then blad(old,116);

         if value then blad(old, 4);

         war:=___rept_ile;
         value:=true;
         __inc(i,a);
        end;

   // odczytaj operator '<'
   '<': if a[i+1] in ['<','=','>'] then
         oper:=OperExt(i,old,'<',a[i+1],value) else
          if value then oper:=OperNew(i,old,'<',value,true) else
           oper:=OperNew(i,old,'M',value,false);

   // odczytaj operator '>'
   '>': if a[i+1] in ['=','>'] then
         oper:=OperExt(i,old,'>',a[i+1],value) else
          if value then oper:=OperNew(i,old,'>',value,true) else
           oper:=OperNew(i,old,'S',value,false);

   // odczytaj operator '='
   '=': if a[i+1]='=' then
         oper:=OperExt(i,old,'=','=',value) else
          if value then oper:=OperNew(i,old,'=',value,true) else
           oper:=OperNew(i,old,'X',value,false);                   // odczyt nr banku przypisanego etykiecie =label

   // odczytaj operator '&'
   '&': if a[i+1]='&' then
         oper:=OperExt(i,old,'&','&',value) else
          oper:=OperNew(i,old,'&',value,true);

   // odczytaj operator '|'
   '|': if a[i+1]='|' then
         oper:=OperExt(i,old,'|','|',value) else
          oper:=OperNew(i,old,'|',value,true);

   // odczytaj operator '!'
   '!': if a[i+1]='=' then
         oper:=OperExt(i,old,'!','=',value) else
          oper:=OperNew(i,old,'!',value,false);

   // odczytaj operator '^'
   '^': if not(value) then begin
         oper:='H'; inc(i)
        end else oper:=OperNew(i,old,'^',value,true);

   // odczytaj operator '/'
   '/': if a[i+1]='*' then begin
         omin_spacje(i,a);
         value:=false;
        end else oper:=OperNew(i,old,'/',value,true);

   // odczytaj operator '*'
   '*': if not(value) then begin
         b:=bank;
         war:=adres;
         value:=true;

         inc(i);

         label_type:='V';

         if not(branch) then begin

          if dreloc.sdx then
           save_rel(adres, -1, blok, reloc_value)
          else
           save_rel(adres, -1, bank, reloc_value);

         end;

        end else oper:=OperNew(i,old,'*',value,true);

   // odczytaj operator '~'
   '~': oper:=OperNew(i,old,'~',value,false);

   // odczytaj operatory '+' '-'
   '+','-':
        oper:=OperNew(i,old,a[i],value,value);

   // odczytaj wartosc decymalna lub wyjatkowo hex 0x...
   '0'..'9':
        begin
         if value or ReadEnum then blad(old,4);

         if (i<length(a)) and (UpCase(a[i+1])='X') and (a[i]='0') then begin  // 0x...

          inc(i);
          tmp:=read_HEX(i,a,old);

         end else                                                             // 0..9
          tmp:=read_DEC(i,a);

         war:=StrToInt(tmp);

         value:=true;
        end;

   // na podstawie typu wyliczeniowego TDIROP
   // ta sama kolejnosc w programie wyliczajacym HASH
   // !!! obliczamy CRC16 dla kolejnych znakow, konczymy gdy kod z zakresu TDIROP !!!
   '.':
    begin
     k:=ord(t_dirop(_unknown));

     tmp:='.';

     inc(i);

     x:=tCRC16[byte($ffff shr 8) xor byte('.')] xor ($ffff shl 8);

     while _alpha(a[i]) and (i<=length(a)) do begin
      byt:=UpCase(a[i]);				// !! duze litery !! bo nie zadziala z przelacznikiem -c
      x:=tCRC16[byte(x shr 8) xor byte(byt)] xor (x shl 8);

      tmp:=tmp+byt;
      inc(i);

      k:=hash[(tCRC16[byte(x shr 8) xor byte('.')] xor (x shl 8)) and $ffff];

      if k in [ord(_or)..ord(_array)] then Break;
     end;

     omin_spacje(i,a);

     case t_dirop(k) of

      _r: begin						// .R
           if ___rept_ile<0 then blad(old,116);

           war:=___rept_ile;
           if not(loop_used) and not(FOX_ripit) then t:=t+' #'+Hex(cardinal(war),2);    // zapisz w pliku LST #numer

           value:=true;
          end;

      _lo: begin					// .LO (expression)
            old_reloc_value_cnt := reloc_value.cnt;
            old_reloc_value_use := reloc_value.use;

            war:=byte( oblicz_wartosc_ogr(a,old,i) );

            reloc_value.use := old_reloc_value_use;
            inc(reloc_value.cnt, old_reloc_value_cnt);

            value:=true;
           end;

      _hi: begin					// .HI (expression)
            old_reloc_value_cnt := reloc_value.cnt;
            old_reloc_value_use := reloc_value.use;

            war:=byte( oblicz_wartosc_ogr(a,old,i) shr 8 );

            reloc_value.use := old_reloc_value_use;
            inc(reloc_value.cnt, old_reloc_value_cnt);

            value:=true;
           end;

     _rnd: begin					// .RND
	    //randomize;
	    war:=random(256);
	    value:=true;
	   end;

     _asize:						// .ASIZE
           begin
	    war:=asize;
	    value:=true;
	   end;

     _isize:						// .ISIZE
           begin
	    war:=isize;
	    value:=true;
	   end;

     _get, _wget, _lget, _dget:
           begin					// .GET, .WGET, .LGET, .DGET
            arg:=0;

            old_reloc_value_cnt := reloc_value.cnt;
            old_reloc_value_use := reloc_value.use;

            if a[i] in AllowStringBrackets then arg:=integer( oblicz_wartosc_ogr(a,old,i) );

            subrange_bounds(old,arg,$FFFF);         // !!! konieczny test

            reloc_value.use := old_reloc_value_use;
            inc(reloc_value.cnt, old_reloc_value_cnt);

            case t_dirop(k) of
              _get: war := t_get[arg];
             _wget: war := Int64(t_get[arg]) + Int64(t_get[arg+1] shl 8);
             _lget: war := Int64(t_get[arg]) + Int64(t_get[arg+1] shl 8) + Int64(t_get[arg+2] shl 16);
             _dget: war := Int64(t_get[arg]) + Int64(t_get[arg+1] shl 8) + Int64(t_get[arg+2] shl 16) + Int64(t_get[arg+3] shl 24);
            end;

            value:=true;
           end;

      _or: oper:=OperExt(k,old,'|','|',value);      // .OR

     _and: oper:=OperExt(k,old,'&','&',value);      // .AND

     _xor: oper:=OperNew(k,old,'^',value,true);     // .XOR

     _not: oper:=OperNew(k,old,'!',value,false);    // .NOT

     _fileexists:				    // .FILEEXISTS
           begin

            if a[i] in AllowStringBrackets then
             txt := ciag_ograniczony(i, a, true)
            else
             txt:= get_datUp(i, a, #0, false);

            k:=1;

            if txt[k] in AllowQuotes then begin

             txt:=get_string(k,txt,old,true);

             txt:=GetFile(txt,a);

	    end;

            war:=ord(TestFile(txt));

	    value:=true;

	   end;

     _len,_filesize,_sizeof:
           begin                                    // .LEN
          // odczytujemy nazwe etykiety

            k:=i;

            if a[i] in AllowStringBrackets then
             txt := ciag_ograniczony(i, a, true)
            else
             txt:= get_datUp(i, a, #0, false);

            v:=1;
            war := get_type(v, txt, old, false, false);


         if not (byte(war) in [1..4] ) then begin

            i:=k;

            txt:=get_labEx(i,a, old);

            k:=1;
            omin_spacje(k, txt);

            if txt[k] in AllowQuotes then begin      // .FILESIZE

             txt:=get_string(k,txt,old,true);

             txt:=GetFile(txt,a);
             if not(TestFile(txt)) then blad(txt,18);

             assignfile(fsize, txt); FileMode:=0; Reset(fsize, 1);
             war:=FileSize(fsize);
             CloseFile(fsize);

            end else begin

             arg:=load_label_ofset(txt, old, true);

             if arg>=0 then
              case t_lab[arg].bnk of
                  __id_proc: war:=t_prc[t_lab[arg].adr].len;            // dlugosc bloku .PROC
                 __id_array: war:=t_arr[t_lab[arg].adr].len;            // dlugosc bloku .ARRAY
                  __id_enum: war:=t_lab[arg].adr;                       // rozmiar .ENUM w bajtach
                __id_struct: war:=t_str[t_lab[arg].adr].siz;            // dlugosc bloku .STRUCT
               __dta_struct: war:=t_str[t_str[t_lab[arg].adr].idx].siz* // rozmiar danych zdefiniowanych przez DTA LABEL_STRUCT
                                  (Int64(t_str[t_lab[arg].adr].ofs) + 1);
               else
                begin

                 war:=t_lab[arg].lln;                        // dlugosc bloku .LOCAL

                 if var_idx>0 then
                  for k := High(t_var)-1 downto 0 do
                   if t_var[k].nam=txt then begin war:=t_var[k].siz; Break end;

                end;

              end;

            end;

         end;

            value:=true;
           end;

     _adr: begin                                    // .ADR label
          // odczytujemy nazwe etykiety
            txt:=get_labEx(i,a, old);

            arg:=load_label_ofset(txt, old, true);

            war:=0;

            if arg>=0 then begin

             old_reloc_value_cnt := reloc_value.cnt;
             old_reloc_value_use := reloc_value.use;

             war:= oblicz_wartosc(txt,old);

             reloc_value.use := old_reloc_value_use;
             inc(reloc_value.cnt, old_reloc_value_cnt);

             case t_lab[arg].bnk of
              __id_proc: dec(war, t_prc[t_lab[arg].adr].ofs);
             else
              dec(war, t_lab[arg].ofs)
             end;

            end;

            value:=true;
           end;

     _def: begin					// .DEF label
          // odczytujemy nazwe etykiety
            txt:=get_labEx(i,a, old);
            arg:=load_label_ofset(txt, old, false);

            war := ord(arg >= 0);	// !!! nie dziala prawidlowo dla .IFNDEF z Exomizera !!!

	    if exclude_proc and (arg >= 0) and (t_lab[arg].bnk = __id_proc) then
	     war := ord(t_lab[arg].use)
	    else
	    if pos('.', txt) > 0 then begin		// sprawdz czy etykieta nie nalezy do procedury

	     while pos('.',txt)>0 do begin

              obetnij_kropke(txt);

              k:=length(txt);				// usun ostatni znak kropki
              SetLength(txt,k-1);
	     end;

             arg:=load_label_ofset(txt, old, false);

	     if exclude_proc and (arg >=0) and (t_lab[arg].bnk = __id_proc) then war := ord(t_lab[arg].use);

	    end;

{
            if arg>=0 then           // !!! koniecznie ta wersja !!!
             war := ord( t_lab[arg].pas>0 )
            else
             war:=0;
}
            value:=true;
           end;

     _zpvar:
           begin
            war:=zpvar;

            value:=true;
           end;

     _array:
           begin

            war:=0;

            if etyArray='' then
             blad(old,15)
            else
             if value then
              get_array(i,a, etyArray, 0)
             else begin
              get_array(i,a, etyArray, adres);
              war:=t_arr[array_idx-1].len;
             end;

            etyArray:='';
            value:=true;

           end;

     else
      blad_und(a,tmp,68);
     end;

    end;

   // odczytaj etykiete i okresl jej wartosc
   // znak ':' oznacza etykiete globalna lub parametr makra
   'A'..'Z','_','?','@',':':
     begin
         petla:=false;  b:=0;  war:=0;  //pomoc:=0;

         if a[i]=':' then

          if _lab_first(a[i+1]) then begin
           petla:=true; inc(i)
          end else
           if _dec(a[i+1]) then begin

            if run_macro then begin
             value:=false; oper:=' ';   Break; // i:=len+1
            end else
             blad(old,8,':');

           end else
            blad(old,4);

         if i<=len then begin

          if value then blad(old,4);

          tmp:=get_lab(i,a, false);  if petla then tmp:=':'+tmp;

          if tmp='@' then                    // Anonymous labels @+[1..9] (forward), @-[1..9] backward
           case a[i] of
            '-': begin
                  k:=anonymous_idx-1; inc(i);

                  if _dec(a[i]) then begin k:=k-StrToInt(a[i]); inc(i) end;

                  test_eol(i,a,a,#0);
                  tmp:=IntToStr(k)+'@';
                 end;

            '+': begin
                  k:=anonymous_idx; inc(i);

                  if _dec(a[i]) then begin k:=k+StrToInt(a[i]); inc(i) end;

                  test_eol(i,a,a,#0);
                  tmp:=IntToStr(k)+'@';
                 end;
           end;


          arg:=load_label_ofset(tmp, old, true);


          if arg>=0 then
           if t_lab[arg].lid and (t_lab[arg].add > pass shl 1) and (t_lab[arg].pas=pass_end) then begin

            if run_macro then txt:=macro_nr+lokal_name else   // !!! nie remowac LOKAL_NAME !!!
             if proc then txt:=proc_name+lokal_name else
              txt:=lokal_name;

            if txt <> tmp+'.' then warning(121, tmp);   // wieloznaczne etykiety LOCAL !!! koniecznie t_lab[x].pas

          end;


      // jesli przetwarzamy makro to nie musza byc zdefiniowane wartosci etykiet
      // w pozostalych przypadkach wystapi blad 'Undeclared label ????'

          if arg<0 then begin
           undeclared:=true;               // wystapila niezdefiniowana etykieta
           value:=false; oper:=' '; Break  // przerywamy obliczanie wyrazenia
          end else
           if (pass=pass_end) and (t_lab[arg].bnk<__id_param) and t_lab[arg].sts then blad_und(old,tmp,112);

          undeclared:=t_lab[arg].sts;      // aktualny status etykiety

          pomoc:=t_lab[arg].adr;

          if (t_lab[arg].typ in ['P','V']) then variable:=true;

          t_lab[arg].use:=true;

          if attribute.atr=__U then begin
           attribute.atr := t_lab[arg].atr;
           attribute.nam := tmp;
          end;


   if arg>=0 then
     case t_lab[arg].bnk of

      __id_struct:  // zamiana struktur na dane DTA, na poczatku sprawdzimy czy 'DTA_USED = true'

   if not(dta_used) then begin

       b   := t_str[pomoc].bnk;
       war := t_str[pomoc].siz;

       if pass=pass_end then begin
        blad(old,79, tmp);
       end;

   end else
      if pass=0 then begin              // teraz nie znamy wszystkich struktur, musimy kończyc

        if a[i]<>'[' then warning(102); // 'Constant expression expected', brakuje indeksu [idx]

      end else begin     // w drugim przebiegu mamy pewnosc ze poznalismy wszystkie struktury

      dta_used:=false;

      struct_used.use:=true;

      save_lst('i');

    // odczytujemy ofset do tablicy 'T_STR'
      ofset:=t_lab[arg].adr;

      struct_used.idx:=ofset;     // w OFSET indeks do pierwszego pola struktury

    // liczba pol struktury
      b := t_str[ofset].ofs;

      inc(ofset);  txt:='';

    // odczytujemy zadeklarowana liczbe elementow danych strukturalnych  [?]
      arg:=integer( oblicz_wartosc_ogr(a,old,i) );

      testRange(old, arg, 62);

      struct_used.cnt:=arg;

      omin_spacje(i,a);

    // odczytujemy wartosci elementow ograniczone nawiasami ( )
      while a[i] ='(' do begin

       tmp:=ciag_ograniczony(i,a,true);

       k:=1; tmp:=get_dat_noSPC(k,tmp,old, #0);
       k:=1;

       SetLength(stos_,1);

     // wczytujemy elementy ograniczone nawiasami, w 'X' jest licznik
       x:=0;
       while k<=length(tmp) do begin

        pomoc:=loa_str_no(t_str[ofset].id, x);  // zawsze musi odnalezc wlasciwe pole struktury

        v:=t_str[pomoc].siz;

//        byt:=tType[v];
//        war:=___wartosc_noSPC(tmp,old,k,',',byt);

        txt:=get_dat(k,tmp,',',false);
        save_dtaS(txt, t_str[pomoc].rpt, v, old);

        inc(x);
//        if pass>0 then
         if x>b then blad(old,40);   // jesli liczba podanych elementow jest wieksza niz w strukturze

        pomoc:=High(stos_);
        stos_[pomoc]:=txt;

        SetLength(stos_,pomoc+2);

        omin_spacje(k,tmp);
        if tmp[k]=',' then __inc(k,tmp) else Break;
       end;

//       if pass>0 then
        if x<>b then blad(old,40);

     // zmniejszamy licznik elementow
       dec(arg); if arg<-1 then blad(old,40);

       omin_spacje(i,a);
      end;

      omin_spacje(i,a);

      value:=( High(stos_) = b );   // jesli podalismy jakies wartosci poczatkowe to VALUE=TRUE

      if not(dreloc.use or dreloc.sdx) then
       if not(value) then new_DOS_header;  // jesli nie podalismy wartosci to musimy wymusic ORG-a

    // !!! nie mozna domyslnie zapisywac zer dla zmiennej strukturalnej !!!
    // !!! bo nie zawsze mozna zapisywac pamiec pod aktualnym adresem !!!

    // reszte elementow struktury wypelniamy ostatnimi wartosciami lub zerami
      while arg>=0 do begin

       for x:=0 to b-1 do begin

        pomoc:=loa_str_no(t_str[ofset].id, x);

        v:=t_str[pomoc].siz;   //byt:=tType[v];

        _hlp:=t_str[pomoc].rpt * v;

        if value then begin
         save_dtaS(stos_[x], t_str[pomoc].rpt, v, old); // nowy adres i zapisanie wartosci poczatkowej struktury
        end else
         if dreloc.use or dreloc.sdx then
          save_dtaS('0', t_str[pomoc].rpt, v, old)
         else begin
          war:=0;
          inc(adres, _hlp);              // nowy adres bez zapisywania wartosci poczatkowej
         end;

       end;

       dec(arg);
      end;

     b:=bank;
     value:=false;
     oper:=' ';
   end;

           __id_define: begin
                        // omin_spacje(i,a);

                         txt := get_define(i, arg, a);

                         dec(i, length(tmp));

                         delete(a, i, length(tmp));

                         insert(txt, a, i);

                         goto LOOP;

                         //inc(i, length(txt));
                         //len:=length(a);

                        end;

            __id_macro: begin

                         blad(old,79, tmp);

                        end;

            __id_enum: begin
                        omin_spacje(i,a);

                        if a[i] in AllowStringBrackets then begin

                         _hlp:=usi_idx;                 // dla enum_name(label1|label2|...)

                         t_usi[usi_idx].lok:=end_idx;
                         t_usi[usi_idx].lab:=tmp;

                         if proc then                   // dopiszemy do listy .USE [.USING]
                          t_usi[usi_idx].nam:=proc_name
                         else
                          t_usi[usi_idx].nam:=lokal_name;

                         inc(usi_idx);
                         SetLength(t_usi, usi_idx+1);

                         ReadEnum:=true;

                         war:=oblicz_wartosc_ogr(a,old,i);

                         ReadEnum:=false;

                         usi_idx:=_hlp;

                        end else begin
                         blad(old,79, tmp);
                        end;

                       end;


            __id_proc: begin
                        b:=t_prc[pomoc].bnk;
                        war:=t_prc[pomoc].adr;

                        if ExProcTest then t_prc[pomoc].use:=true;  // procedura .PROC musi byc asemblowana

                        save_relAddress(arg, reloc_value);
                       end;

            __id_ext:  begin
                        if blocked then blad_und(old,tmp,41);

                        if not(branch) then begin

                          if vector then
                           _hlp:=adres
                          else
                           _hlp:=adres+1;

                          if dreloc.use then dec(_hlp, rel_ofs);

                          t_ext[ext_idx].adr := _hlp;
                          t_ext[ext_idx].bnk := bank;
                          t_ext[ext_idx].idx := pomoc;

                          inc(ext_idx);

                          if ext_idx>High(t_ext) then SetLength(t_ext,ext_idx+1);
                        end;

                        ext_used.use:=true;
                        ext_used.idx:=pomoc;
                        ext_used.siz:=t_extn[pomoc].siz;

                        inc(reloc_value.cnt);
                       end;

            __id_smb:  begin
                        if blocked then blad_und(old,tmp,41);

                        if not(branch) then begin
                         save_rel(adres,pomoc,0, reloc_value);
                         t_smb[pomoc].use:=true;
                         war:=__rel;
                        end;

                       end;

           __id_array: begin
                        b:=t_arr[pomoc].bnk;
                        war:=t_arr[pomoc].adr;

                        war:=war + read_elements(i,a, pomoc,false);

                        save_relAddress(arg, reloc_value);
                       end;

         __dta_struct: begin

                        save_relAddress(arg, reloc_value);

                        b:=t_str[pomoc].bnk;
                        war:=t_str[pomoc].adr;

                        ofset:=integer( oblicz_wartosc_ogr(a,old,i) );

                        subrange_bounds(old,ofset,t_str[pomoc].ofs);

                        arg:=t_str[t_lab[arg].adr].idx;

                        ofset:=ofset * t_str[arg].siz;   // indeks * dlugosc_struktury

                        if a[i]='.' then begin
                          inc(i);
                          txt:=get_lab(i,a, false);

                         // szukamy w T_STR
                          pomoc:=loa_str(txt, t_str[arg].id);

                          if pomoc>=0 then
                           inc(ofset,t_str[pomoc].ofs)
                          else
                           if pass=pass_end then blad_und(old,txt,46);

                        end;

                        inc(war,ofset);
                       end;
           else
            begin

          // wystapi blad 'Address relocation overload'
          // jesli dokonujemy operacji na wiecej niz jednej relokowalnej etykiecie

             save_relAddress(arg, reloc_value);

             b:=t_lab[arg].bnk;				// bank przypisany etykiecie

             if dreloc.use or dreloc.sdx then begin
              b:=t_lab[arg].blk;			// blok przypisany etykiecie
              if reloc_value.use and (reloc_value.cnt>1) then blad(old,85);
             end;

             war:=t_lab[arg].adr;

             while pos('.',tmp)>0 do begin

              obetnij_kropke(tmp);

              k:=length(tmp);				// usun ostatni znak kropki
              SetLength(tmp,k-1);

              arg:=l_lab(tmp);

	      if arg<0 then arg:=l_lab(lokal_name+tmp);

              pomoc:=t_lab[arg].adr;

              if (arg>=0) and ExProcTest then
               if t_lab[arg].bnk=__id_proc then begin
                t_prc[pomoc].use:=true;			// procedura .PROC musi byc asemblowana
                Break;
               end;

             end;

            end;

           end;

          value:=true;
         end;


      // wyjatkowo dla PASS=0 i prawdopodobnego odwolania do tablicy przyjmij wartosc =0
         omin_spacje(i,a);
         if a[i]='[' then
          if pass<pass_end then
           exit
          else
           blad_und(old,tmp,5);

        end;

   // odczytaj wartosc hexadecymalna
   '$': begin

         if value or ReadEnum then blad(old,4);

         tmp:=read_HEX(i,a,old);

         war:=StrToInt(tmp);

         value:=true;
        end;

   // odczytaj wartosc binarna lub potraktuj '%' jako operator
   // lub jako numer parametru dla makra gdy wystapily znaki '%%'
   '%': if a[i+1]='%' then begin

//        if not(_dec(a[i+2])) then blad(old,47);      // %%0..9

//         b:=0; war:=0;
         value:=false; oper:=' ';  //Break; //i:=len+1
         inc(i, 2);

        end else
         if value then
          oper:=OperNew(i,old,'%',value,true)
         else begin
           inc(i);     // omin pierwszy znak '%'
//           war:=get_value(i,a,'B',old);

           tmp:='';
           while _bin(a[i]) do begin tmp:=tmp+a[i]; __inc(i,a) end;

           if not(test_param(i,a)) then
            if tmp='' then blad(old,8,a[i]);

           if ReadEnum then blad(old,4);

//           war:=BinToInt(tmp);
           war:=0;

(*----------------------------------------------------------------------------*)
(*  realizacja zamiany ciagu zero-jedynkowego na wartosc decymalna            *)
(*----------------------------------------------------------------------------*)
          if tmp<>'' then begin

            k:=Length(tmp);

           //remove leading zeros
            pomoc:=1;
            while tmp[pomoc]='0' do inc(pomoc);

           //do the conversion
            for ofset:=k downto pomoc do
             if tmp[ofset]='1' then
              war:=war+(1 shl (k-ofset));

          end;

           value:=true;
         end;

   // odczytaj string ograniczony apostrofami '',""
   '''','"':
        begin
         if value then blad(old,4);

         k:=ord(a[i]);
         tmp:=get_string(i,a,old,true);

         if length(tmp)>2 then blad(old,3);                // maksymalnie 1 znak, lub 2 znaki dla 65816

         if chr(k)='''' then
          war:=ord(tmp[1])
         else
          war:=ata2int(ord(tmp[1]));

	 if length(tmp) = 2 then
         if chr(k)='''' then
          war:=war shl 8 + ord(tmp[2])
         else
          war:=war shl 8 + (ata2int(ord(tmp[2])));

         byt:=a[i+1];

         if not(_lab_firstEx(byt) or _dec(byt) or (byt in ['$','%'])) then
          inc(war,test_string(i,a,'F'));

         value:=true;
        end;

   // odczytaj wartosc miedzy { }
   '{': begin
         if value then blad(old,4);

         klamra_used := true;

         petla:=dreloc.use;       // blokujemy relokowalnosc DRELOC.USE=FALSE
         dreloc.use:=false;

         tmp:=ciag_ograniczony(i,a,true);            // test na poprawnosc nawiasow
         k:=1; nul:=oblicz_mnemonik(k,tmp,old);

         dreloc.use:=petla;       // przywracamy poprzednia wartosc DRELOC.USE

         klamra_used := false;

         war:=nul.h[0];

         nul.l:=0;

         value:=true;
        end;

   // odczytaj wartosc miedzy [ ] ( )
   '[','(':
        begin
         if value then blad(old,4);

         old_reloc_value_cnt := reloc_value.cnt;
         old_reloc_value_use := reloc_value.use;

         war:=oblicz_wartosc_ogr(a,old,i);

         reloc_value.use := old_reloc_value_use;
         inc(reloc_value.cnt, old_reloc_value_cnt);

         value:=true;
        end;

   // jesli napotkasz spacje to zakoncz przetwarzanie
   // do 'value' wpisz 'false' aby nie traktowal tego jako liczby
   ' ',#9:
        begin
         value:=false; oper:=' ';  Break; //i:=len+1
        end;

  else
   blad(old,8,a[i]);
  end;


// jesli przetwarzamy wartosc numeryczna to zapisz na stosie
// tą wartosc i operator
  if value then begin

   op[op_idx]:='+';

  // przetworz operatory z 'OP' cofajac sie
   for k:=op_idx downto 1 do
    case op[k] of
     '-': war := -war;
     'M': war := byte(war);
     'S': war := byte(war shr 8);
     'H': war := byte(war shr 16);
//     'I': war := byte(war shr 24);
     '!': war := ord(war=0);
     '~': war := not(war);
     'X': war := b;
    end;

   if op[0]='-' then begin war:=-war; op[0]:='+' end;

   stos[j].znak := op[0];
   stos[j].wart := war;

   cash[pos(op[0],prior)-1]:=op[0];

  // zeruj indeks do tablicy dynamicznej OP
   op_idx:=0; oper:=' ';

   inc(j);
//   if j>High(stos) then SetLength(stos,j+1);

  end else begin

   op[op_idx] := oper;

   inc(op_idx);
 //  if op_idx>High(op) then SetLength(op,op_idx+1);

  end;

 end;


 if not(overflow) then
  if oper<>' ' then blad(old,23);


 if reloc_value.cnt>1 then blad(old,85);


// obliczenie wartosci wg piorytetu obliczen
// na koncu dodawaj tak dlugo az nie uzyskasz wyniku
 len:=0; war:=0;

 while cash[len]=' ' do inc(len);     // omijaj puste operatory
 if len>=sizeof(cash) then exit;      // nie wystapil zaden operator

 stos[0].znak:='+'; stos[0].wart:=0;
 stos[j].znak:='+'; stos[j].wart:=0;
 inc(j);

// SetLength(stos,j+1);


 while j>1 do begin
 // 'petla=true' jesli nie wystapi zaden operator
 // 'petla=false' jesli wystapi operator
  i:=0; petla:=true;

  while i<=j-2 do begin

    war  := stos[i].wart;
    oper := stos[i+1].znak;
    iarg := stos[i+1].wart;

 // obliczaj wg kolejnosci operatorow z 'prior'
 // operatory '/','*','%' maja ten sam piorytet, stanowią wyjątek

     if (oper=cash[len]) or ((oper in ['/','*','%']) and (len in [5..7])) then begin
        case oper of
         '+': war := war + iarg;
         '&': war := war and iarg;
         '|': war := war or iarg;
         '^': war := war xor iarg;
         '*': war := war * iarg;

         '/','%':
              if iarg=0 then begin

               overflow:=true;

               if pass=pass_end then
                blad(old,26)
               else
                war:=0;

              end else
               case oper of
                '/': war := war div iarg;
                '%': war := war mod iarg;
               end;

         '=': war := ord(war=iarg);
         'A': war := ord(war<>iarg);
         'B': war := ord(war<=iarg);
         '<': war := ord(war<iarg);
         'C': war := ord(war>=iarg);
         '>': war := ord(war>iarg);
         'D': war := war shl iarg;
         'E': war := war shr iarg;
         'F': war := ord(war<>0) and ord(iarg<>0);
         'G': war := ord(war<>0) or ord(iarg<>0);
        end;

 // obliczyl nowa wartosc, skasuj znak

      stos[i].wart   := war;
      stos[i+1].znak := ' ';

      inc(i); petla:=false;
     end;

  inc(i)
  end;

// przepisz elementy ktore maja niepusty znak na poczatek tablicy STOS
  k:=0;

  for i:=0 to j-1 do
   if stos[i].znak<>' ' then begin
    stos[k] := stos[i];
    inc(k)
   end;

  j:=k;

  if petla and (len<sizeof(prior)-1) then begin
   inc(len);
   while cash[len]=' ' do inc(len);
  end;

 end;


 if overflow then          // konieczny warunek dla .MACRO
  Result := 0
 else
  Result := war;

end;


function oblicz_wartosc_noSPC(var zm,old:string; var i:integer; const sep,typ:Char): Int64;
(*----------------------------------------------------------------------------*)
(*  pobieramy ciag pomijajac spacje, nastepnie obliczamy jego wartosc         *)
(*----------------------------------------------------------------------------*)
var txt: string;
begin

 txt:=get_dat_noSPC(i,zm,old,sep);

 Result:=oblicz_wartosc(txt,old);

 omin_spacje(i,zm);

 wartosc(old,Result,typ);

end;


function get_expres(var i:integer; var a,old:string; const tst:Boolean): Int64;
(*----------------------------------------------------------------------------*)
(*  pobierz ciag znakow ograniczony przecinkiem i oblicz jego wartosc         *)
(*  nie wczytuj nawiasow zamykajacych ')'                                     *)
(*  jesli TST = TRUE to sprawdzaj czy to koniec wyrazenia                     *)
(*----------------------------------------------------------------------------*)
var k: integer;
    tmp: string;
begin
 k:=i;
 tmp:=get_dat(k,a,')',false);

 tmp:=a;
 SetLength(tmp,k-1);  // tmp:=copy(a,1,k-1);

 Result:=oblicz_wartosc_noSPC(tmp,old,i,',','F');

 if tst then
  if a[i]<>',' then blad(old,52) else inc(i);
end;


procedure _siz(const t: Boolean);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

  t_siz[siz_idx - ord(t)].siz:=dreloc.siz;

//  if t then
//   t_siz[siz_idx-1].siz:=dreloc.siz
//  else
//   t_siz[siz_idx].siz:=dreloc.siz;

end;


procedure _sizm(const a: byte);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 if reloc then t_siz[siz_idx-1].lsb := a;

end;


procedure oblicz_dane(var i:integer; var a,old:string; const typ: byte);
(*----------------------------------------------------------------------------*)
(*  zwracamy wartosci liczbowe dla ciagu DTA, .BYTE, .WORD, .LONG, .DWORD     *)
(*----------------------------------------------------------------------------*)
(*  B( -> BYTE                                                                *)
(*  A( -> WORD                                                                *)
(*  V( -> VECTOR (WORD)                                                       *)
(*  L( -> BYTE   (bits 0..7)                                                  *)
(*  H( -> BYTE   (bits 8..15)                                                 *)
(*  M( -> BYTE   (bits 16..23)                                                *)
(*  G( -> BYTE   (bits 24..31)                                                *)
(*  T( -> LONG                                                                *)
(*  E( -> LONG                                                                *)
(*  F( -> DWORD                                                               *)
(*  R( -> DWORD  (odwrocona kolejnosc)                                        *)
(*  C' -> ATASCII                                                             *)
(*  D' -> INTERNAL                                                            *)
(*  sin(centre,amp,size[,first,last])                                         *)
(*  cos(centre,amp,size[,first,last])                                         *)
(*  rnd(min,max)                                                              *)
(*----------------------------------------------------------------------------*)
var op_, default: char;
    sin_a, sin_b, sin_c, sin_d, sin_e, x, len, k: integer;
    war: Int64;
    invers: byte;
    value, nawias, ciag, yes: Boolean;
    tmp: string;
begin
 omin_spacje(i,a);

 if empty or enum.use then blad(old,58);

 war:=0; invers:=0;

 value:=false; nawias:=false; ciag:=false;

 if not(pisz) then branch:=false;

 reloc := false;

 data_out := true;

 tmp:=' ';


// ------------------ okreslenie domyslnego typu wartosci ---------------------

  default := tType[typ];
  op_:=default;

  dreloc.siz:=relType[typ];

// ----------------------------------------------------------------------------


 if not(pisz) and test_char(i,a) then    // jesli brakuje danych to generuj domyslnie zera
  if defaultZero then begin
   save_dta(cardinal(war),tmp,op_,invers);
   exit;
  end else
   blad(old,23);


 if struct.use then blad(old,58);

 vector:=true;

 if not(pisz) then dta_used:=true;


 len:=length(a);

 while i<=len do begin

// SIN, RND
  if UpCase(a[i]) in ['C','R','S'] then begin

   x:=ord(UpCase(a[i+1])) shl 16+ord(UpCase(a[i+2])) shl 8+ord(a[i+3]);

  CASE x of
 // IN(, OS(
   $494E28, $4F5328: begin
    inc(i,3);

   // sprawdzamy poprawnosc nawiasow
    k:=i;
    tmp:=ciag_ograniczony(k,a,true);

    value:=true; invers:=0; tmp:='';

    inc(i);
    sin_a:=integer( get_expres(i,a,old,true) );
    sin_b:=integer( get_expres(i,a,old,true) );
    sin_c:=integer( get_expres(i,a,old,false) );

    if sin_c<=0 then begin blad(old,0); Break end;

    sin_d:=0;
    sin_e:=sin_c-1;

    if a[i]=',' then begin

     inc(i);
     sin_d:=integer( get_expres(i,a,old,true) );
     sin_e:=integer( get_expres(i,a,old,false) );

     inc(i);
    end else inc(i);


    while sin_d <= sin_e do begin

     if x=$4F5328 then
      war:= sin_a + round(sin_b * cos(sin_d * 2 * pi / sin_c))    // COS
     else
      war:= sin_a + round(sin_b * sin(sin_d * 2 * pi / sin_c));   // SIN

     war:=wartosc(old,war,op_);
     save_dta(cardinal(war),tmp,op_,invers);

     inc(sin_d);
    end;

    omin_spacje(i,a);

   end;

 // ND(
   $4E4428: begin
    inc(i,3);

   // sprawdzamy poprawnosc nawiasow
    k:=i;
    tmp:=ciag_ograniczony(k,a,true);

    value:=true; invers:=0; tmp:='';

    inc(i);
    sin_a:=integer( get_expres(i,a,old,true) );
    sin_b:=integer( get_expres(i,a,old,true) );
    sin_c:=integer( get_expres(i,a,old,false) );
    inc(i);

    sin_d:=sin_b-sin_a;

    randomize;
    for x:=0 to sin_c-1 do begin

     war:=sin_a+Int64(random(sin_d+1));

     war:=wartosc(old,war,op_);
     save_dta(cardinal(war),tmp,op_,invers)
    end;

    omin_spacje(i,a);
   end;

  END;    //end case

  end;


  case UpCase(a[i]) of
   'A','B','E','F','G','H','L','M','R','T','V':

          begin
            k:=i;

            if a[i+1] in AllowWhiteSpaces then begin
             __inc(i,a);

             if a[i]='(' then dec(i) else i:=k;
            end;

            if a[i+1]='(' then begin
            // pobierz ciag ograniczony nawiasami ( )
             if value then blad(old,4);

             op_:=UpCase(a[k]);  inc(i);
            // sprawdzamy poprawnosc
             k:=i;
             tmp:=ciag_ograniczony(k,a,true);
             nawias:=true;

            // dane inne niz 2 bajtowe nie sa relokowalne w przypadku SPARTA DOS X
            // relokowalne sa wszystkie jesli uzylismy dyrektywy .RELOC
             if dreloc.use then begin
//              if op_='R' then branch:=true else branch:=false;
              branch := (op_='R');

              case op_ of
               'E','T': dreloc.siz:=relType[3];
               'A','V': dreloc.siz:=relType[2];
                   'F': dreloc.siz:=relType[4];
                   'L': dreloc.siz:='<';
                   'H': dreloc.siz:='>';
              else
               dreloc.siz:=relType[1];
              end;

              _siz(false);

             end else
//              if op_ in ['E','F','R','T'] then branch:=true else branch:=false;
              branch := (op_ in ['E','F','G','M','R','T']);

             inc(i);             // omin nawias otwierajacy

            end else begin

             if dreloc.use then _siz(false);

             if value then blad(old,4);
             war:=get_expres(i,a,old, false);
             value:=true;

            { if reloc and not(nawias) then             ????????????????????????
              if pass=pass_end then warning(116);  }

             if pisz then end_string := end_string + '$' + hex(cardinal(war),4);
            end;

          end;


   'C','D':
          begin
            k:=i;

            if a[i+1] in AllowWhiteSpaces then begin
             __inc(i,a);

             if a[i] in AllowQuotes then dec(i) else i:=k;
            end;

            if a[i+1] in AllowQuotes then begin
           // pobierz ciag ograniczony apostrofami '' lub ""
             op_:=UpCase(a[k]);  inc(i);

            end else begin

             if dreloc.use then _siz(false);

             if value then blad(old,4);
             war:=get_expres(i,a,old, false);
             value:=true;

            { if reloc and not(nawias) then             ????????????????????????
              if pass=pass_end then warning(116);    }

             if pisz then end_string := end_string + '$' + hex(cardinal(war),4);
            end;

          end;

   '''','"': begin
              if value then blad(old,4);

//              if aray then
              if not(op_ in ['C','D']) then
               if a[i]='"' then op_:='D' else op_:='C';

              tmp:=get_string(i,a,old,true);
              war:=0; ciag:=true;

	      if a[i] = '^' then begin
	       tmp[length(tmp)] := chr(ord(tmp[length(tmp)]) or $80);

	       inc(i);
	      end;

              invers:=byte( test_string(i,a,'B') );
              value:=true;

	      if a[i] = '^' then begin
	       tmp[length(tmp)] := chr(ord(tmp[length(tmp)]) or $80);

	       inc(i);
	      end;

              if pisz then end_string := end_string + tmp;
             end;


   '(': begin
         if nawias then blad(old,107);

         nawias:=true;
         inc(i);
        end;

   ')': if nawias and value then begin
         value:=false; nawias:=false; inc(i);

         omin_spacje(i,a);

         if not(test_char(i,a)) then         // jesli nie ma konca linii to jedynym
          if a[i]<>',' then blad(old,107);   // akceptowanym znakiem jest znak ','

        end else blad(old,4);


   ',': begin
         __inc(i,a); invers:=0; value:=false;

         if a[i]=',' then blad(old,4) else
          if test_char(i,a) then blad(old,23);  // jesli koniec linii to blad 'Unexpected end of line'

         if not(nawias) then op_:=default;
        end;


   ' ',#9: omin_spacje(i,a);


   '/': case a[i+1] of
         '/': Break;
         '*': begin tmp:=''; search_comment_block(i,a, tmp); if komentarz then Break end;
        else
         blad(old,4);   // value:=false; i:=length(a)+1
        end;

   ';','\': Break;                                   // value:=false; i:=length(a)+1

  else
       begin

         if _eol(a[i]) then Break;

         if dreloc.use then _siz(false);

         if value then blad(old,4);

         war:=get_expres(i,a,old, false);
         value:=true;

         if pisz then end_string := end_string + '$' + hex(cardinal(war),4);

       end;
  end;


  if dta_used then
   if value then begin

    if not(ciag) then
     if op_ in ['C','D'] then op_:='B';


    if reloc and dreloc.use then begin
     dec(war,rel_ofs);

     _sizm(byte(war));    // zapisze tylko gdy RELOC=TRUE

     reloc:=false;
    end;

    if not(pisz) then begin

     if ext_used.use and (op_ in ['L','H']) then
      case op_ of
       'L': t_ext[ext_idx-1].typ:='<';
       'H': begin t_ext[ext_idx-1].typ:='>'; t_ext[ext_idx-1].lsb:=byte(war) end;
      end;

     war:=wartosc(old,war,op_);

     if proc then
      yes := t_prc[proc_nr-1].use
     else
      yes := true;

     if yes then save_dta(cardinal(war),tmp,op_,invers);
    end else
     branch:=true;           // jesli PISZ=TRUE to nie ma relokowalnosci

    ciag:=false;
   end;

  omin_spacje(i,a);
 end;

 vector:=false; dta_used:=false;
end;


function value_code(var a: Int64; var old: string; const test:Boolean): char;
(*----------------------------------------------------------------------------*)
(*  przedstawiamy wartosc w postaci kodu literowego 'Z', 'Q', 'T' , 'D'       *)
(*  kody literowe symbolizuja typ wartosci BYTE, WORD, LONG, DWORD            *)
(*----------------------------------------------------------------------------*)
var x: cardinal;
begin
 Result:='D';

 x:=cardinal( abs(a) );

 case x of
              0..$FF: Result:='Z';
         $100..$FFFF: Result:='Q';
     $10000..$FFFFFF: if test then Result:='T' else blad(old,14);
// $1000000..$FFFFFFFF: Result:='D';
 else
  if not(test) then blad(old,0);
 end;

end;


procedure reg_size(const i:byte; const a: t_MXinst);
(*----------------------------------------------------------------------------*)
(*  nowe rozmiary rejestrow dla operacji sledzenia SEP, REP                   *)
(*  A: t_MXinst		SEP (set bits), REP (reset bits)		      *)
(*  bit 0 -> 16 bit							      *)
(*  bit 1 -> 8 bit							      *)
(*----------------------------------------------------------------------------*)
begin

 if i and $10 <> 0 then
  if a = REP then
    isize := 16
  else
    isize := 8;

 if i and $20 <> 0 then
  if a = REP then
    asize := 16
  else
    asize := 8;

end;


procedure test_reg_size(var a:string; const b,i,l:byte);
(*----------------------------------------------------------------------------*)
(*  sprawdzamy rozmiar rejestrow dla wlaczonej opcji sledzenia SEP, REP       *)
(*  B: BYTE	reg size = [8,16]					      *)
(*  I: BYTE	code size = [1..3]					      *)
(*  L: BYTE	LONGA | LONGI = [0,8,16]				      *)
(*----------------------------------------------------------------------------*)
begin

 if b=8 then begin
  if (i>2) and (l in [0,16]) then blad(a,63);
 end else
  if (i<3) and (l in [0,8]) then blad(a,63);

end;


procedure test_siz(var a:string; var siz:Char; const x:Char; out pomin:Boolean);
(*----------------------------------------------------------------------------*)
(*  sprawdzamy identyfikator rozmiaru                                         *)
(*----------------------------------------------------------------------------*)
begin
 if siz in [' ',x] then siz:=x else blad(a,14);

 pomin:=true;
end;


function adr_label(const n: t_mads; const tst:Boolean): cardinal;
(*----------------------------------------------------------------------------*)
(*  szukamy wartosci dla etykiety o nazwie z MADS_STACK[N].NAM, jesli nie     *)
(*  zostaly zdefiniowane etykiety z MADS_STACK wowczas przypisujemy im        *)
(*  wartosci z MADS_STACK[N].ADR                                              *)
(*----------------------------------------------------------------------------*)
var i: integer;
    txt: string;

begin
 Result:=0;

 txt:=mads_stack[ord(n)].nam;  i:=load_lab(txt,false);

 if tst then
  if i<0 then begin
   Result:=mads_stack[ord(n)].adr;    // brak deklaracji dla etykiety z TXT

   s_lab(txt,Result,bank,txt,'@');
  end;

 if i>=0 then Result:=t_lab[i].adr;   // odczytujemy wartosc etykiety
end;


procedure test_skipa;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var i: integer;
begin

   if t_bck[1]=adres then exit;

   t_bck[0] := t_bck[1];
   t_bck[1] := adres;

   skip_use:=false;

   for i := 0 to High(t_skp)-1 do
    if t_skp[i].use then begin

     t_skp[i].adr:=adres;

     inc(t_skp[i].cnt);

     if t_skp[i].cnt>1 then
      t_skp[i].use := false
     else
      skip_use:=true;

    end;

end;


procedure addResult(var hlp, Res: int5);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var i: integer;
begin
  for i:=0 to hlp.l-1 do Res.h[Res.l+i]:=hlp.h[i];
  inc(Res.l, hlp.l);
end;


function asm_mnemo(var txt, old:string): int5;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var i: integer;
begin
 i:=1; Result:=oblicz_mnemonik(i,txt, old);

 inc(adres, Result.l);
end;


function moveAXY(var mnemo,zm,zm2, old: string): int5;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var tmp: string;
    hlp: int5;
    r: byte;
    v: integer;
begin

   mnemo[1]:='L'; mnemo[2]:='D';                  // LD?
   tmp:=mnemo + #32 + zm;
   Result:=asm_mnemo(tmp,old);


   if regAXY_opty and not(dreloc.use) and not(dreloc.sdx) then
   if zm[1] in ['#','<','>'] then begin

    v:=Result.h[1];

    case mnemo[3] of
     'A': r := 0;
     'X': r := 1;
//     'Y': r := 2;
    else
     r:=2;
    end;

    if regOpty.use then
     if regOpty.reg[r]=v then Result.l:=0;

    regOpty.reg[r]:=v;
   end;


   mnemo[1]:='S'; mnemo[2]:='T';                  // ST?
   tmp:=mnemo + #32 + zm2;
   hlp:=asm_mnemo(tmp,old);

   addResult(hlp, Result);

   Result.tmp:=hlp.h[0];
end;


function adrMode(const a: string): byte;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 Result:=fCRC16(a);

 if Result in [$60..$7e] then
  dec(Result,$60)
 else
  Result:=0;

end;


procedure save_fake_label(var ety,old:string; const tst:cardinal);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var war: integer;
begin

   war:=load_lab(ety,false);        // uaktualniamy wartosc etykiety

   if war<0 then
    s_lab(ety,tst,bank,old,ety[1])
   else
    t_lab[war].adr:=tst;

end;


function TypeToByte(const a: char): byte;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 case a of
  'B': Result := 1;
  'W': Result := 2;
  'L': Result := 3;
  'D': Result := 4;
 else
   Result := 0;
 end;

end;


function ValueToType(const a: Int64): byte;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 case abs(a) of
           0..$FF: Result:=1;
      $100..$FFFF: Result:=2;
  $10000..$FFFFFF: Result:=3;
 else
  Result:=4
 end;

end;


function getByte(var pom: string; const ile: byte; const ch: Char): string;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 Result:='';

      case ch of
       'W': case ile of
             2: pom[1]:='>';
             1: pom[1]:='<';
            end;

       'L': case ile of
             3: pom[1]:='^';
             2: pom[1]:='>';
             1: pom[1]:='<';
            end;

       'D': case ile of
             4: Result:='>>24';
             3: pom[1]:='^';
             2: pom[1]:='>';
             1: pom[1]:='<';
            end;
       end;

end;


function oblicz_mnemonik(var i:integer; var a,old:string): int5;
(*----------------------------------------------------------------------------*)
(*  funkcja zwraca wartosc typu INT5                                          *)
(*  INT5.L  -> liczba bajtow                                                  *)
(*  INT5.H  -> kod maszynowy mnemonika, ARGUMENTY                             *)
(*----------------------------------------------------------------------------*)
type
 t_ads = record
          kod: byte;
          ads: cardinal;
         end;

var j, m, idx, len: integer;
    op_, mnemo, mnemo_tmp, zm, tmp, str, pom, add: string;
    war, war_roz, help: Int64;
    code, ile, k, byt: byte;
    op, siz: char;
    test, zwieksz, incdec, mvnmvp, pomin, opty, isvar: Boolean;
    branch_run, old_run_macro: Boolean;
    tryb: cardinal;
    hlp: int5;
    par: _strArray;

const
 maska: array [1..23] of cardinal=(
 $01,$02,$04,$08,$10,$20,$40,$80,$100,$200,$400,$800,$1000,$2000,
 $4000,$8000,$10000,$20000,$40000,$80000,$100000,$200000,$400000);

 addycja: array [1..48] of byte=(
 0,0,4,8,8,12,16,20,20,24,28,44,
 0,0,8,4,8,16,20,24,24,32,32,32,
 4,0,8,4,8,16,20,24,24,32,32,32,
 0,0,0,133,22,8,0,240,0,0,216,0);

 addycja_16: array [1..207] of byte=(
 0,0,0,2,2,4,6,8,8,12,14,16,17,18,20,20,22,24,28,30,32,34,48,
 0,0,0,2,2,8,6,4,8,16,14,16,17,18,24,24,22,32,32,30,32,34,48,
 0,0,0,0,0,0,0,0,0,0,2,0,0,0,0,0,0,0,0,0,0,0,220,
 0,0,0,0,0,0,0,0,0,0,16,0,0,0,0,0,0,0,0,0,32,144,48,
 0,0,0,0,0,0,0,101,0,8,0,0,0,0,16,0,0,0,24,0,0,0,0,
 0,0,0,0,0,0,0,0,0,56,0,0,0,0,16,0,0,0,58,0,0,0,0,
 0,0,0,0,0,0,0,146,0,0,0,0,114,0,0,0,0,0,0,0,0,0,0,
 0,0,0,0,0,140,0,0,0,148,0,0,0,0,156,0,0,0,164,0,0,0,0,
 0,0,0,0,0,204,0,0,0,212,0,0,0,0,220,0,0,0,228,0,0,0,0);

 // kod maszynowy nielegalnego mnemonika w pierwszej adresacji (CPU 6502)
 m6502ill: array [96..118] of t_ads =
 (
 (kod:$03; ads:$000006E5),	// 96 ASO
 (kod:$23; ads:$000006E5),	// 97 RLN
 (kod:$43; ads:$000006E5),	// 98 LSE
 (kod:$63; ads:$000006E5),	// 99 RRD
 (kod:$83; ads:$00000125),	// 100 SAX
 (kod:$9F; ads:$80000365),	// 101 LAX
 (kod:$C3; ads:$000006E5),	// 102 DCP
 (kod:$E3; ads:$000006E5),	// 103 ISB
 (kod:$03; ads:$00000008),	// 104 ANC
 (kod:$43; ads:$00000008),	// 105 ALR
 (kod:$63; ads:$00000008),	// 106 ARR
 (kod:$83; ads:$00000008),	// 107 ANE Unstable
 (kod:$A3; ads:$00000008),	// 108 ANX Unstable
 (kod:$C3; ads:$00000008),	// 109 SBX
 (kod:$A3; ads:$00000200),	// 110 LAS Unstable
 (kod:$83; ads:$00000240),	// 111 SHA Unstable
 (kod:$83; ads:$00000200),	// 112 SHS Unstable
 (kod:$86; ads:$00000200),	// 113 SHX
 (kod:$80; ads:$00000400),	// 114 SHY
 (kod:$1A; ads:$00000000),	// 115 NPO
 (kod:$40; ads:$0000008C),	// 116 DOP
 (kod:$00; ads:$00000420),	// 117 TOP
 (kod:$02; ads:$00000000)	// 118 CIM
 );

 // kod maszynowy mnemonika w pierwszej adresacji (CPU 6502)
 m6502: array [0..55] of t_ads =
 (
 (kod:$A1; ads:$000006ED),	// LDA
 (kod:$9E; ads:$8000032C),	// LDX
 (kod:$9C; ads:$800004AC),	// LDY
 (kod:$81; ads:$000006E5),	// STA
 (kod:$82; ads:$00000124),	// STX
 (kod:$80; ads:$000000A4),	// STY
 (kod:$61; ads:$000006ED),	// ADC
 (kod:$21; ads:$000006ED),	// AND
 (kod:$02; ads:$000004B4),	// ASL
 (kod:$E1; ads:$000006ED),	// SBC
 (kod:$14; ads:$00000020),	// JSR
 (kod:$40; ads:$00000820),	// JMP
 (kod:$42; ads:$000004B4),	// LSR
 (kod:$01; ads:$000006ED),	// ORA
 (kod:$C1; ads:$000006ED),	// CMP
 (kod:$BC; ads:$8000002C),	// CPY
 (kod:$DC; ads:$8000002C),	// CPX
 (kod:$C2; ads:$000004A4),	// DEC
 (kod:$E2; ads:$000004A4),	// INC
 (kod:$41; ads:$000006ED),	// EOR
 (kod:$22; ads:$000004B4),	// ROL
 (kod:$62; ads:$000004B4),	// ROR
 (kod:$00; ads:$00000000),	// BRK
 (kod:$18; ads:$00000000),	// CLC
 (kod:$58; ads:$00000000),	// CLI
 (kod:$B8; ads:$00000000),	// CLV
 (kod:$D8; ads:$00000000),	// CLD
 (kod:$08; ads:$00000000),	// PHP
 (kod:$28; ads:$00000000),	// PLP
 (kod:$48; ads:$00000000),	// PHA
 (kod:$68; ads:$00000000),	// PLA
 (kod:$40; ads:$00000000),	// RTI
 (kod:$60; ads:$00000000),	// RTS
 (kod:$38; ads:$00000000),	// SEC
 (kod:$78; ads:$00000000),	// SEI
 (kod:$F8; ads:$00000000),	// SED
 (kod:$C8; ads:$00000000),	// INY
 (kod:$E8; ads:$00000000),	// INX
 (kod:$88; ads:$00000000),	// DEY
 (kod:$CA; ads:$00000000),	// DEX
 (kod:$8A; ads:$00000000),	// TXA
 (kod:$98; ads:$00000000),	// TYA
 (kod:$9A; ads:$00000000),	// TXS
 (kod:$A8; ads:$00000000),	// TAY
 (kod:$AA; ads:$00000000),	// TAX
 (kod:$BA; ads:$00000000),	// TSX
 (kod:$EA; ads:$00000000),	// NOP
 (kod:$10; ads:$00000002),	// BPL
 (kod:$30; ads:$00000002),	// BMI
 (kod:$D0; ads:$00000002),	// BNE
 (kod:$90; ads:$00000002),	// BCC
 (kod:$B0; ads:$00000002),	// BCS
 (kod:$F0; ads:$00000002),	// BEQ
 (kod:$50; ads:$00000002),	// BVC
 (kod:$70; ads:$00000002),	// BVS
 (kod:$20; ads:$00000024) 	// BIT
 );

 // kod maszynowy mnemonika w pierwszej adresacji (CPU 65816)
 m65816: array [0..93] of t_ads =
 (
 (kod:$A1; ads:$000F7EE9),	// LDA
 (kod:$9E; ads:$800282A0),	// LDX
 (kod:$9C; ads:$800442A0),	// LDY
 (kod:$81; ads:$000F7E69),	// STA
 (kod:$82; ads:$00008220),	// STX
 (kod:$80; ads:$00004220),	// STY
 (kod:$61; ads:$000F7EE9),	// ADC
 (kod:$21; ads:$000F7EE9),	// AND
 (kod:$02; ads:$00044320),	// ASL
 (kod:$E1; ads:$000F7EE9),	// SBC
 (kod:$20; ads:$40400600),	// JSR
 (kod:$4C; ads:$20700600),	// JMP
 (kod:$42; ads:$00044320),	// LSR
 (kod:$01; ads:$000F7EE9),	// ORA
 (kod:$C1; ads:$000F7EE9),	// CMP
 (kod:$BC; ads:$800002A0),	// CPY
 (kod:$DC; ads:$800002A0),	// CPX
 (kod:$3A; ads:$02044320),	// DEC
 (kod:$1A; ads:$01044320),	// INC
 (kod:$41; ads:$000F7EE9),	// EOR
 (kod:$22; ads:$00044320),	// ROL
 (kod:$62; ads:$00044320),	// ROR
 (kod:$00; ads:$00000000),	// BRK
 (kod:$18; ads:$00000000),	// CLC
 (kod:$58; ads:$00000000),	// CLI
 (kod:$B8; ads:$00000000),	// CLV
 (kod:$D8; ads:$00000000),	// CLD
 (kod:$08; ads:$00000000),	// PHP
 (kod:$28; ads:$00000000),	// PLP
 (kod:$48; ads:$00000000),	// PHA
 (kod:$68; ads:$00000000),	// PLA
 (kod:$40; ads:$00000000),	// RTI
 (kod:$60; ads:$00000000),	// RTS
 (kod:$38; ads:$00000000),	// SEC
 (kod:$78; ads:$00000000),	// SEI
 (kod:$F8; ads:$00000000),	// SED
 (kod:$C8; ads:$00000000),	// INY
 (kod:$E8; ads:$00000000),	// INX
 (kod:$88; ads:$00000000),	// DEY
 (kod:$CA; ads:$00000000),	// DEX
 (kod:$8A; ads:$00000000),	// TXA
 (kod:$98; ads:$00000000),	// TYA
 (kod:$9A; ads:$00000000),	// TXS
 (kod:$A8; ads:$00000000),	// TAY
 (kod:$AA; ads:$00000000),	// TAX
 (kod:$BA; ads:$00000000),	// TSX
 (kod:$EA; ads:$00000000),	// NOP
 (kod:$10; ads:$00000002),	// BPL
 (kod:$30; ads:$00000002),	// BMI
 (kod:$D0; ads:$00000002),	// BNE
 (kod:$90; ads:$00000002),	// BCC
 (kod:$B0; ads:$00000002),	// BCS
 (kod:$F0; ads:$00000002),	// BEQ
 (kod:$50; ads:$00000002),	// BVC
 (kod:$70; ads:$00000002),	// BVS
 (kod:$24; ads:$100442A0),	// BIT
 (kod:$64; ads:$08044220),	// STZ
 (kod:$DE; ads:$80000080),	// SEP
 (kod:$BE; ads:$80000080),	// REP
 (kod:$10; ads:$00000220),	// TRB
 (kod:$00; ads:$00000220),	// TSB
 (kod:$80; ads:$00000012),	// BRA
 (kod:$FE; ads:$80000080),	// COP
 (kod:$54; ads:$00000004),	// MVN
 (kod:$44; ads:$00000004),	// MVP
 (kod:$60; ads:$00000010),	// PER = PEA rell (push effective address relative)
 (kod:$C3; ads:$00001000),	// PEI = PEA (zp) (push effective address indirect)
 (kod:$62; ads:$04001090),	// PEA = PEA
 (kod:$8B; ads:$00000000),	// PHB
 (kod:$0B; ads:$00000000),	// PHD
 (kod:$4B; ads:$00000000),	// PHK
 (kod:$DA; ads:$00000000),	// PHX
 (kod:$5A; ads:$00000000),	// PHY
 (kod:$AB; ads:$00000000),	// PLB
 (kod:$2B; ads:$00000000),	// PLD
 (kod:$FA; ads:$00000000),	// PLX
 (kod:$7A; ads:$00000000),	// PLY
 (kod:$6B; ads:$00000000),	// RTL
 (kod:$DB; ads:$00000000),	// STP
 (kod:$5B; ads:$00000000),	// TCD
 (kod:$1B; ads:$00000000),	// TCS
 (kod:$7B; ads:$00000000),	// TDC
 (kod:$3B; ads:$00000000),	// TSC
 (kod:$9B; ads:$00000000),	// TXY
 (kod:$BB; ads:$00000000),	// TYX
 (kod:$CB; ads:$00000000),	// WAI
 (kod:$42; ads:$00000000),	// WDM
 (kod:$EB; ads:$00000000),	// XBA
 (kod:$FB; ads:$00000000),	// XCE
 (kod:$3A; ads:$00000000),	// DEA
 (kod:$1A; ads:$00000000),	// INA
 (kod:$14; ads:$00000400),	// JSL
 (kod:$4E; ads:$00000400),	// JML
 (kod:$80; ads:$00000010) 	// BRL
 );

begin
 Result.l:=0;

 if a='' then blad(old,12);

 op_:=''; siz:=' '; op:=' ';

 war_roz:=0;

 mvnmvp:=true; pomin:=false; ext_used.use:=false;

 zwieksz:=false; incdec:=false; reloc:=false; branch:=false;

 mne_used:=false;

 attribute.atr:=__U;

 omin_spacje(i,a);

 m:=i;                  // zapamietaj pozycje

// pobierz nazwe rozkazu, oblicz jego CRC16
 mnemo:='';  mnemo_tmp:='';

 if _lab_first(a[i]) then
  while _lab(a[i]) or (a[i] in [':','%']) do begin
   mnemo:=mnemo+UpCase(a[i]);
   mnemo_tmp:=mnemo_tmp+UpCas_(a[i]);
   inc(i);
  end;


 // asemblujemy procedury .PROC do ktorych wystapilo odwolanie w programie
 // przelacznik -x 'Exclude unreferenced procedures' musi byc uaktywniony
 if exclude_proc then
  if proc and (pass>0) then
   if not(t_prc[proc_nr-1].use) then begin

    if VerifyProc then begin

     exProcTest  := false;
     exclude_proc:= false;

     Result:=oblicz_mnemonik(m,a,old);     // dodatkowy test linii gdy EXCLUDE_PROC:=FALSE

     if Result.l<__equ then Result.l:=0;

     exProcTest  := true;
     exclude_proc:= true;

     i:=m;
    end;

    exit;
   end;


 // jesli czytamy tablice ARRAY to linia zaczyna sie znakiem '(' lub '['
 // jesli innym niz znaki konca linii to blad 'Improper syntax'
  if aray then begin
   Result.l:=__array_run; i:=1; exit
  end;


 // jesli brakuje mnemonika to sprawdz czy nie jest to cyfra (blad 'Illegal instruction')
 // w innym przypadku nie przetwarzamy tego i wychodzimy
  if mnemo='' then
   if _dec(a[i]) or (a[i] in ['$','%']) then
    blad(old,12)
   else
    exit;


 // wyjatek znak '=' jest rownowazny 'EQU'
 // dla etykiety zaczynajacej sie od pierwszego znaku w wierszu
 if mnemo='=' then begin Result.l:=__equ; exit end;


 // jesli wystepuje znak ':' tzn ze laczymy mnemoniki w stylu XASM'a
 j:=pos(':',mnemo);
 if j>0 then begin
   Result.i:=i;
   i:=m;                      // modyfikujemy wartosc spod adresu 'i'
   Result.l:=__xasm;
   exit;
 end;


// sprawdz czy to operacja przypisania '=', 'EQU', 'SET', '+=', '-=', '++', '--'
// dla etykiety poprzedzonej minimum jedna spacja lub tabulatorem

 j:=i;

 omin_spacje(i,a);

 tmp:=''; k:=0;

 if UpCase(a[i]) in ['E','S'] then begin      // EQU, SET
  tmp:=get_datUp(i,a,#0,false);
  omin_spacje(i,a);
  if (length(tmp)=3) and not(test_char(i,a,' ',#0)) then k:=fASC(tmp);
 end else begin

  while a[i] in ['=','+','-'] do begin
   tmp:=tmp+a[i];
   if a[i]='=' then Break;
   __inc(i,a);
  end;

  k:=fCRC16(tmp);

 end;

//  if (tmp='EQU') or (tmp='=') or (tmp='+=') or (tmp='-=') or (tmp='++') or (tmp='--') then begin
 if k in [__equ+1, __set+1, __nill] then begin
   i:=m;                      // modyfikujemy wartosc spod adresu 'i'

   if k=__set+1 then
    Result.l:=__addSet
   else
    Result.l:=__addEqu;

   exit;
 end;


 i:=j;


 len:=length(mnemo);


// sprawdz czy wystapilo rozszerzenie mnemonika
 if len=5 then
  if a[i-2]='.' then
                    case UpCase(a[i-1]) of
                     'A','W','Q': siz:='Q';
                         'B','Z': siz:='Z';
                         'L','T': siz:='T';
                    end;


// poszukaj mnemonika w tablicy HASH
 k:=0;

 if len=3 then
  k:=fASC(mnemo)
 else
  if siz<>' ' then begin		// jesli SIZ<>' ' tzn ze jest to 3-literowy mnemonik z rozszerzeniem

    k:=fASC(mnemo);

    if k>0 then SetLength(mnemo,3);	// jesli taki mnemonik istnieje to OK,
					// !!! w przeciwnym wypadku zapewne jest to jakies makro !!!
  end;

 // symbole mnemonikow maja kody <1..92>
 // symbole mnemonikow 6502      <1..56>, nielegale <96..118>
 // symbole mnemonikow 65816     <57..92>

 if not(opt and opt_C>0) then begin
  if k in [57..92] then k:=0;		// gdy 6502 to mozna uzywac mnemonikow 65816 jako makra itp.
 end else
  if k in [96..118] then k:=0;		// gdy 65816 to mozna uzywac mnemonikow nielegali 6502 jako makra itp.


// w IDX przechowujemy aktualny adres asemblacji, tej zmiennej nie uzyjemy w innym celu

if k in [__cpbcpd..__jskip] then begin

 if adres<0 then
  if pass=pass_end then blad(old,10);

 if siz<>' ' then blad(old,33);

 if not(k in [__BckSkp, __phrplr]) then begin	// __BckSkp i __phrplr nie potrzebuja parametrow

  omin_spacje(i,a);

  SetLength(par, 1);

   while not(test_char(i,a)) do begin		// odczyt parametrow makro rozkazu, 'GetParameters' nie nadaje sie do tego
    idx:=High(par);
    par[idx]:=get_dat(i,a,' ',true);

    SetLength(par, idx+2);

    omin_spacje(i,a);
   end;

  case k of					// test liczby parametrow makro rozkazu
   __inwdew, __addsub: begin idx:=1; j:=1 end;
   __movaxy, __cpbcpd: begin idx:=2; j:=2 end;
   __adwsbw, __adbsbb: begin idx:=2; j:=3 end;
  else
   idx:=0;
  end;

  if idx>0 then
   if High(par)<idx then blad(old,23) else
    if High(par)>j then blad(old,4);

  tmp:=par[0];
 end;


 idx := adres;

 Result.l:=0;


 case k of

// obsluga PHR, PLR
 __phrplr:
 begin

  Result.l:=5;

  if mnemo[2]='H' then begin
   Result.h[0]:=$48;
   Result.h[1]:=$8a;
   Result.h[2]:=$48;
   Result.h[3]:=$98;
   Result.h[4]:=$48;
  end else begin
   Result.h[0]:=$68;
   Result.h[1]:=$a8;
   Result.h[2]:=$68;
   Result.h[3]:=$aa;
   Result.h[4]:=$68;
  end;

 end;


// obsluga INW, INL, IND, DEW, DEL, DED
 __inwdew:
 begin
  Result.l:=0;

  ile:=TypeToByte(mnemo[3]);

  mnemo[3]:='C';


  if mnemo[1]='I' then begin		// INW, INL, IND

   str:='##INC#DEC'+IntToStr(ora_nr);

   j:=load_lab(str,false);		// odczytujemy wartosc etykiety

   if j>=0 then
    tryb:=t_lab[j].adr
   else
    tryb:=0;

   j:=0;

   while ile>0 do begin
     zm:=mnemo + #32 + tmp + '+' + IntToStr(j);
     hlp:=asm_mnemo(zm,old);
     addResult(hlp, Result);

     if ile>1 then begin
      zm:='BNE '+IntToStr(tryb);
      hlp:=asm_mnemo(zm,old);
      addResult(hlp, Result);
     end;

     inc(j);
     dec(ile);
   end;

   save_fake_label(str,old, adres);

   inc(ora_nr);

  end else begin			// DEW, DEL, DED

   if pass = pass_end then warning(127);// Register A is changed

   byt:=0;

   while byt<ile-1 do begin

     zm:='LDA ' + tmp + '+' + IntToStr(byt);
     hlp:=asm_mnemo(zm,old);
     addResult(hlp, Result);

     str:='##INC#DEC'+IntToStr(Int64(ora_nr)+byt);

     j:=load_lab(str,false);		// odczytujemy wartosc etykiety

     if j>=0 then
      tryb:=t_lab[j].adr
     else
      tryb:=0;

     zm:='BNE '+IntToStr(tryb);
     hlp:=asm_mnemo(zm,old);
     addResult(hlp, Result);

     inc(byt);
   end;

   inc(byt);

   while byt<>0 do begin

     if byt<>ile then begin
      str:='##INC#DEC'+IntToStr(Int64(ora_nr)+byt-1);
      save_fake_label(str,old, adres);
     end;

     zm:='DEC ' + tmp + '+' + IntToStr(Int64(byt)-1);
     hlp:=asm_mnemo(zm,old);
     addResult(hlp, Result);

     dec(byt);
   end;

   inc(ora_nr, ile-1);
  end;

 end;


// obsluga ADW, SBW
 __adwsbw:
 begin
    str:=par[1];
    pom:=par[2];

    test:=false;
    if pom='' then
     pom:=tmp                        // w POM wynik operacji
    else
     test:=true;

    if tmp[1]='#' then blad(old,14);

    mnemo[3] := 'C';                 // ADC, SBC

    if mnemo[1]='S' then
     zm:='SEC'
    else
     zm:='CLC';

    Result:=asm_mnemo(zm,old);

    zm:='LDA ' + tmp;

    hlp:=asm_mnemo(zm,old);
    addResult(hlp, Result);

    ile:=hlp.h[0];

    opty:=false;
    if ile=$B1 then opty:=true;      // wystepuje LDA(),Y


    if not(ile in [$A5,$AD,$B5,$BD]) then
     test:=true;                     // nie przejdzie krotsza wersja z SCC, SCS


    if str[1]='#' then begin
     str[1]:='+';
     branch:=true;                   // nie relokujemy, testujemy tylko wartosc
     war:=oblicz_wartosc(str,old);
     wartosc(old,war,'A');

     str[1]:='<';
     zm:=mnemo + #32 + str;
     hlp:=asm_mnemo(zm,old);
     addResult(hlp, Result);

     zm:='STA '+pom;
     hlp:=asm_mnemo(zm,old);
     addResult(hlp, Result);

     if not(test) and (war<256) then begin

      macroCmd:=true;       // dla prawidlowego test_skipa

      if mnemo[1]='S' then
       zm:='SCS'
      else
       zm:='SCC';

      hlp:=asm_mnemo(zm,old);
      addResult(hlp, Result);

      if mnemo[1]='S' then
       zm:='DEC ' + tmp + '+1'
      else
       zm:='INC ' + tmp + '+1';

      hlp:=asm_mnemo(zm,old);
      addResult(hlp, Result);

      macroCmd:=false;

     end else begin

      if opty then begin

       zm:='iny';                     // tylko w ten sposob przez ASM_MNEMO
       hlp:=asm_mnemo(zm, old);       // inaczej nie bedzie relokowalnosci
       addResult(hlp,Result);

       add:='';
      end else
       add:='+1';

      zm:='LDA ' + tmp + add;
      hlp:=asm_mnemo(zm,old);
      addResult(hlp, Result);

      str[1]:='>';
      zm:=mnemo + #32 + str;
      hlp:=asm_mnemo(zm,old);
      addResult(hlp, Result);

      if pos(',Y', AnsiUpperCase(pom))=0 then add:='+1';

      zm:='STA ' + pom + add;
      hlp:=asm_mnemo(zm,old);
      addResult(hlp, Result);
     end;

    end else begin
     zm:=mnemo + #32 + str;
     hlp:=asm_mnemo(zm,old);
     addResult(hlp, Result);

     byt:=hlp.h[0];

     zm:='STA ' + pom;
     hlp:=asm_mnemo(zm,old);
     addResult(hlp, Result);

     if opty then begin

      zm:='iny';
      hlp:=asm_mnemo(zm, old);
      addResult(hlp,Result);

      add:='';
     end else
      add:='+1';


     if byt in [$71,$F1] then begin         // $71 = ADC(),Y ; $F1 = SBC(),Y

      if not(opty) then begin

       zm:='iny';
       hlp:=asm_mnemo(zm, old);
       addResult(hlp,Result);

       if (ile in [$b6,$b9,$be]) then add:='';
      end;

     end else
      if not(opty and (byt=$79)) then str:=str+'+1';

     zm:='LDA ' + tmp + add;
     hlp:=asm_mnemo(zm,old);
     addResult(hlp, Result);

     zm:=mnemo + #32 + str;
     hlp:=asm_mnemo(zm,old);
     addResult(hlp, Result);

     if pos(',Y', AnsiUpperCase(pom))=0 then add:='+1';

     zm:='STA ' + pom + add;
     hlp:=asm_mnemo(zm,old);
     addResult(hlp, Result);
    end;


    case pom[length(pom)] of
     '+': zm:='iny';
     '-': zm:='dey';
    else
     zm:='';
    end;

    if zm<>'' then begin
     hlp:=asm_mnemo(zm, old);
     addResult(hlp,Result);
    end;

 end;


// obsluga ADB, SBB
 __adbsbb:
 begin
    str:=par[1];
    pom:=par[2];

    Result.l:=0;

    if pom='' then begin
     pom:=tmp;

     if tmp[1]='#' then
      if str[1]<>'#' then pom:=str;

    end;

    if tmp<>'@' then begin
     zm:='LDA ' + tmp;
     Result:=asm_mnemo(zm,old);
    end;

    if mnemo[1]='S' then
     zm:='SUB '
    else
     zm:='ADD ';

    zm:=zm + str;
    hlp:=asm_mnemo(zm,old);
    addResult(hlp, Result);

    if pom<>'@' then begin
     zm:='STA ' + pom;
     hlp:=asm_mnemo(zm,old);
     addResult(hlp, Result);
    end;
 end;


// obsluga ADD, SUB
 __addsub:
 begin
  inc(adres);

  mnemo[2]:=mnemo[3];
  mnemo[3]:='C';
  Result.l:=1;

  if mnemo[1]='A' then
   Result.h[0]:=$18               // kod dla CLC
  else
   Result.h[0]:=$38;              // kod dla SEC

  zm:=mnemo + #32 + tmp;
  hlp:=asm_mnemo(zm,old);
  addResult(hlp, Result);
 end;


// obsluga MVA, MVX, MVY, MWA, MWX, MWY
 __movaxy:
 begin
  zm:=par[1];

  op:=tmp[1];
  Result.l:=0;

  opty:=false;

  if op='#' then regOpty.blk:=true;   // wlaczamy przetwarzanie makro-rozkazow MW?#, MV?#


  if mnemo[2]='W' then begin          // MW?

    if op='#' then begin

     variable:=false;                 // domyslnie VARIABLE=FALSE, czyli nie jest to zmienna

     tmp[1]:='+';
     branch:=true;                    // nie relokujemy, testujemy tylko wartosc
     war:=oblicz_wartosc(tmp,old);
     wartosc(old,war,'A');

//     if not(dreloc.use) and not(dreloc.sdx) then
      if not(variable) then           // jesli nie jest to zmienna to testujemy dalej
       if byte(war)=byte(war shr 8) then opty:=true;

     tmp[1]:='<';
    end;

    Result:=moveAXY(mnemo,tmp,zm,old);

    test:=false;


    if not(opty) then
    if op='#' then
     tmp[1]:='>'
    else                                     // wyjątek MWA (ZP),Y ADR
     if Result.h[0]<>$B1 then begin          // $B1 = LDA(ZP),Y

      if Result.tmp=$91 then begin
       if not(Result.h[0] in [$b6,$b9,$be]) then tmp:=tmp+'+1';
      end else
       tmp:=tmp+'+1';

     end else begin                    // $C8 = INY

      if Result.h[Result.l-1]<>$c8 then begin
       pom:='iny';                     // tylko w ten sposob przez ASM_MNEMO
       hlp:=asm_mnemo(pom, old);       // inaczej nie bedzie relokowalnosci
       addResult(hlp,Result);
      end;

      test:=true;
     end;

    if Result.tmp=$91 then begin      // $91 = STA(ZP),Y

     if (Result.h[0]<>$B1) and (Result.h[Result.l-1]<>$c8) then begin
      pom:='iny';
      hlp:=asm_mnemo(pom, old);
      addResult(hlp,Result);
     end;

    end else
     if test then begin						// $96 = STX Z,Y
      if not(Result.tmp in [$96,$99]) then zm:=zm+'+1';		// $99 = STA Q,Y
     end else
      zm:=zm+'+1';

  end;


  if opty then begin

   tmp:=mnemo + #32 + zm;
   hlp:=asm_mnemo(tmp, old);

  end else
   hlp:=moveAXY(mnemo,tmp,zm,old);	// MV?


  addResult(hlp,Result);

  regOpty.blk:=false;			// wylaczamy przetwarzanie makro-rozkazow MWA, MVA itp.
 end;


// obsluga JEQ, JNE, JPL, JMI, JCC, JCS, JVC, JVS
 __jskip:
 begin

  mnemo[1]:='B';			// zamieniamy pseudo rozkaz na mnemonik
  k:=fASC(mnemo);			// wyliczamy kod dla mnemonika

  branch:=true;				// nie relokujemy
  war:=oblicz_wartosc(tmp,old);

  test:=false;

  war:=war-2-adres;

  if (war<0) and (abs(war)-128 > 0) then test:=true;
  if (war>0) and (war-127 > 0) then test:=true;


//  j := load_lab(tmp, false);
//  if (j >= 0) and (war > 0) and (t_lab[j].lop > 0) then test:=true;	// przeciw 'infinite loop'


  if pass = pass_end then
   if test then begin

    if BranchTest then warning(125, lokal_name+tmp);

   end else
    if (word(adres) shr 8 <> word(adres + war + 2) shr 8) then begin

     if BranchTest then warning(126, lokal_name+tmp);

    end;


//  if (word(adres) shr 8 <> word(adres + war + 2) shr 8) then test:=true;


  if not(test) then begin

   Result.l:=2;
   Result.h[0]:=ord(m6502[k-1].kod) {xor $20};		// kod maszynowy mnemonika w pierwszej adresacji 6502
   Result.h[1]:=byte(war);

  end else begin

   if (pass = pass_end) and (t_lab[j].lop = 1) then begin
     t_lab[j].lop := 2;
     if BranchTest then warning(125, lokal_name+tmp)
   end;

   inc(adres,2);

   Result.l:=2;
   Result.h[0]:=ord(m6502[k-1].kod) xor $20;		// kod maszynowy mnemonika w pierwszej adresacji 6502
   Result.h[1]:=3;

   zm:='JMP ' + tmp;
   hlp:=asm_mnemo(zm,old);
   addResult(hlp,Result);
  end;

 end;


// sprawdzamy czy nie sa to pseudo rozkazy skoku
// req, rne, rpl, rmi, rcc, rcs, rvc, rvs  -> b??  skok do tylu
// seq, sne, spl, smi, scc, scs, svc, svs  -> b??  skok do przodu

 __BckSkp:
   begin

    if mnemo[1]='R' then begin

     if (pass=pass_end) and skip_xsm then warning(99);  // Repeating only the last instruction

     if t_bck[0]<0 then begin
      if pass=pass_end then blad(old,110);              // No instruction to repeat
      war:=0;
     end else
      war:=t_bck[0];

    end else begin
     war:=t_skp[skip_idx].adr;

     t_skp[skip_idx].use:=true;

     t_skp[skip_idx].cnt:=0 + ord(macrocmd);

     inc(skip_idx);
     if skip_idx>High(t_skp) then SetLength(t_skp, skip_idx+1);
    end;

     war:=war-2-adres;

     if (war<0) and (abs(war)-128>0) then war:=abs(war)-128;
     if (war>0) and (war-127>0) then dec(war, 127); //war:=war-127;

     if (pass = pass_end) and (word(adres) shr 8 <> word(adres + war + 2) shr 8) then begin

       if BranchTest then warning(126, lokal_name+tmp);

     end;


     mnemo[1]:='B';              // zamieniamy pseudo rozkaz na mnemonik
     k:=fASC(mnemo);             // wyliczamy kod dla mnemonika

     code:=m6502[k-1].kod;       // kod maszynowy mnemonika w pierwszej adresacji 6502

     if not(xasmStyle) then begin
      omin_spacje(i,a);            // !!! koniecznie zaremowane, inaczej
      test_eol(i,a,old,#0);        // !!! nie zadziala np. 'ldx:dex $100','tya #0' , 'lda:cmp:req 20'
     end;

     Result.l := 2;
     Result.h[0] := code;
     Result.h[1] := byte(war);
     inc(adres,2);
   end;

// CPB, CPW, CPL, CPD
 __cpbcpd:
   begin
    pom:=par[1];

    ile:=TypeToByte(mnemo[3]);

    Result.l:=0;


    str:='##CMP#'+IntToStr(ora_nr);

    j:=load_lab(str,false);        // odczytujemy wartosc etykiety

    if j>=0 then
     tryb:=t_lab[j].adr
    else
     tryb:=0;

    test := (tmp[1]='#');
    opty := (pom[1]='#');


    if (tmp='@') and (ile<>1) then blad(old,58);


    variable:=false;               // domyslnie VARIABLE=FALSE, czyli nie jest to zmienna

    if opty then begin
     pom[1]:='+';
     branch:=true;                 // nie relokujemy, testujemy tylko wartosc
     war:=oblicz_wartosc(pom,old);

     pom[1]:='#';
    end;

    isvar:=variable or TestWhileOpt;


    while ile>0 do begin

     if test then
      add:=getByte(tmp, ile, mnemo[3])
     else
      add:='+'+IntToStr(Int64(ile)-1);

     if tmp<>'@' then begin
      zm:='LDA '+tmp + add;
      hlp:=asm_mnemo(zm,old);
      addResult(hlp, Result);
     end;


     if opty then
      add:=getByte(pom, ile, mnemo[3])
     else
      add:='+'+IntToStr(Int64(ile)-1);


     zm:='CMP '+pom + add;
     hlp:=asm_mnemo(zm,old);

     if not(isvar) and (hlp.l=2) and (hlp.h[0]=$c9) and (hlp.h[1]=0) then
      dec(adres, 2)                                    // jesli CMP #0 to anuluj
     else
      addResult(hlp, Result);


     if ile>1 then begin
      zm:='BNE '+IntToStr(tryb);
      hlp:=asm_mnemo(zm,old);
      addResult(hlp, Result);
     end;

     dec(ile);
    end;

    str:='##CMP#'+IntToStr(ora_nr);
    save_fake_label(str,old, adres);

    TestWhileOpt:=true;

    inc(ora_nr);
   end;

 end;

 adres := idx;

 regOpty.use := ( k = __movaxy );

 mne_used := true;		// zostal odczytany jakis mnemonik
 exit;				// !!! KONIEC !!! zostal odczytany i zdekodowany makro-rozkaz
end;


// sprawdz czy to nazwa makra
 if k=0 then begin

    idx:=load_lab(mnemo_tmp,false);	// poszukaj w etykietach

    if idx<0 then begin
     if pass=pass_end then blad_und(old,mnemo,35);
     exit;
    end;

    if t_lab[idx].bnk=__id_ext then	// symbol external
     if t_extn[t_lab[idx].adr].prc then begin

      tmp:='##'+t_extn[t_lab[idx].adr].nam;

      Result.i:=t_lab[l_lab(tmp)].adr;
      Result.l:=__proc_run;

      exit;
     end;


//    if (t_lab[idx].bnk=__id_macro) then begin Result.l:=__nill; exit end;

    if t_lab[idx].bnk>=__id_macro then begin
     Result.l:=byte(t_lab[idx].bnk);
     Result.i:=t_lab[idx].adr;
    end else
     if pass=pass_end then blad_und(old,mnemo,35);

    exit;
 end;


 dec(k);			// !!! koniecznie


// znalazl pseudo rozkaz
 if k>=__equ then
  if siz<>' ' then
   blad(old,33)
  else begin
   Result.l:=k; exit
  end;


 if first_org and (opt and opt_H>0) then blad(old,10);


// jesli nie przetwarzamy makro-rozkazow MWA, MVA itp. to blokujemy optymalizacje rejestrow
 if not(regOpty.blk) then begin
  regOpty.use:=false;

  regOpty.reg[0]:=-1;
  regOpty.reg[1]:=-1;
  regOpty.reg[2]:=-1;
 end;


//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!//
// na podstawie kodu maszynowego CODE mozna juz okreslic jaki to rozkaz       //
// nie trzeba porownywac stringow, czy zamieniac mnemonik na wartosc cyfrowa  //
// w celu pozniejszego porownania                                             //
// od tego momentu zmienna K przechowuje numer rozkazu !!!                    //
//!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!//

 if (opt and opt_C>0) then begin
  code:=m65816[k].kod;           // kody maszynowe 65816 sa z przedzialu <0..91>
  tryb:=m65816[k].ads;           // kod maszynowy mnemonika w pierwszej adresacji 65816
 end else begin

  if k in [96..118] then begin
   code:=m6502ill[k].kod;        // kody maszynowe 6502 illegal sa z przedzialu <96..118>
   tryb:=m6502ill[k].ads;        // kod maszynowy mnemonika w pierwszej adresacji 6502

   if pass=pass_end then
    if k in [107,108,110,111,112] then warning(120, mnemo);

  end else begin
   code:=m6502[k].kod;           // kody maszynowe 6502 sa z przedzialu <0..55>
   tryb:=m6502[k].ads;           // kod maszynowy mnemonika w pierwszej adresacji 6502
  end;

 end;


// w .STRUCT i .ARRAY nie ma mozliwosci uzywania rozkazow CPU
// podobnie w bloku EMPTY (.ds) nie moga wystepowac rozkazy CPU
 if struct.use or aray or enum.use or empty then blad(old,58);


// jesli mnemonik nie wymaga argumentu to skoncz
 if tryb=0 then begin

  if siz<>' ' then blad(old,33);

  if not(xasmStyle) then begin
   omin_spacje(i,a);            // !!! koniecznie zaremowane, inaczej
   test_eol(i,a,a,#0);          // !!! nie zadziala np. 'ldx:dex $100','tya #0' , 'lda:cmp:req 20'
  end;

  Result.l:=1; Result.h[0]:=code;

  mne_used := true;              // zostal odczytany jakis mnemonik

  exit;
 end;


// omin spacje i przejdz do argumentu
 omin_spacje(i,a);


 if _lab_first(a[i]) then begin					// sprawdz czy etykieta konczy sie znakiem ':'

  j:=i;

  tmp:=get_lab(i,a,false);

  if (tmp <> '') and (a[i] = ':') then begin

   old_run_macro := run_macro;
   run_macro     := false;

   if a[i+1] = ':' then begin
    s_lab(tmp, adres+1, bank, zm, tmp[1]);			// etykieta globalna do automodyfikacji kodu

    inc(i);
   end else
    save_lab(tmp, adres+1, bank, zm);      			// etykieta lokalna do automodyfikacji kodu

   run_macro     := old_run_macro;

   inc(i);
   omin_spacje(i,a);
  end else
   i:=j;

 end;


// if (a[i]='#') and (a[i] in ['<','>']) then inc(i);  // !!! to nie jest kompatybilne !!!

// jesli wystepuja operatory #<, #> to omin pierwszy znak i pozostaw <,>
{ if a[i]='#' then begin                               // jesli odremowac to zle liczy !!! lda #>dl1^>dl2 !!!
  idx:=i;                                              // !!! tak musi zostac !!!
  __inc(i,a);                                          // lda #>   nie moze byc tym samym co
  if not(a[i] in ['<','>','^']) then i:=idx;           // lda >    ta operacja
 end;   }


 // pobierz operator argumentu do 'OP'
 // nie dotyczy to rozkazow MVN i MVP (65816)
 if not(code in [68,84]) then begin

  mvnmvp:=false;
  if a[i] in ['#','<','>','^'] then begin
   if not(dreloc.use) then branch:=true;             // nie relokuj tego rozkazu
   op:=a[i]; inc(i)
  end else op:=' ';

  if (a[i]='@') and test_char(i+1,a,' ',#0) then begin op:='@'; inc(i) end;

  if (op='@') then
   if (siz<>' ') then blad(old,33) else test_eol(i,a,a,#0);
 end;

 omin_spacje(i,a);

 // wyjatki dla ktorych rozmiar rejestru jest staly
 if (opt and opt_C>0) and (op='#') then
  case code of
    98: test_siz(a,siz,'Q',pomin);		// PEA #Q
   254: test_siz(a,siz,'Z',pomin);		// COP #Z
   190: test_siz(a,siz,'Z',pomin);		// REP #Z
   222: test_siz(a,siz,'Z',pomin);		// SEP #Z
  end;


  zm:=get_dat_noSPC(i,a,old,';');

 if zm<>'' then
 if (zm[2]=':') and (UpCase(zm[1]) in ['A','Z']) then begin		// wymuszenie trybu A-BSOLUTE, Z-ERO PAGE w stylu XASM
  case UpCase(zm[1]) of
   'A': siz:='Q';
   'Z': siz:='Z';
  end;

  zm:=copy(zm,3,length(zm));
 end;


 tmp:='';

 // jesli brak argumentu przyjmij domyslnie aktualny adres '*'
 // lub operator '@' gdy ASL , ROL , LSR , ROR
 // lub operator '@' dla INC, DEC gdy CPU=65816
  if (zm='') and (op=' ') then begin

   if (code in [2,34,66,98]) or ((opt and opt_C>0) and (code in [26,58])) then
    op:='@'
   else begin
    zm:='*';
    if not(klamra_used) then
     if pass=0 then blad(old,23);            // 'Default addressing mode' -67- wycofany
   end;

  end;


// jesli jest nawias otwierajacy '(' lub '[' to sprawdz poprawnosc
// i czy nie ma miedzy nimi spacji
 if zm<>'' then begin
  j:=1;

 if (op=' ') and (zm[1] in AllowStringBrackets) then begin

 tmp:=get_dat_noSPC(j,zm,a,',');

 if length(tmp)=2 then blad(old,14);      // nie bylo argumentu pomiedzy nawiasami

 // jesli po nawiasie wystapi znak inny niz ',',' ',#0 to BLAD

  omin_spacje(j,zm);
  test_eol(j,zm,a,',');

 // przepisz znak nastepujacy po ',' do 'OP_'
 if zm[j]=',' then begin

  __inc(j,zm);

  if test_param(j,zm) then begin Result.l:=__nill; exit end else
  if UpCase(zm[j]) in ['X','Y','S'] then begin
   op_:=op_+UpCase(zm[j]); //zm[j]:=' ';

    if zm[j+1] in ['+','-'] then begin

     if UpCase(zm[j])='S' then blad(old,4);       // + - nie moze byc dla 'S'

     incdec:=true;

      case zm[j+1] of
       '-': //war_roz:=oblicz_wartosc('{de'+zm[j]+'}',a);
            if UpCase(zm[j])='X' then war_roz:=$CA else war_roz:=$88;   // dex, dey
       '+': //war_roz:=oblicz_wartosc('{in'+zm[j]+'}',a);
            if UpCase(zm[j])='X' then war_roz:=$E8 else war_roz:=$C8;   // inx, iny
      end;

     test_eol(j+2,zm,a,#0);
    end else test_eol(j+1,zm,a,#0);

  end else blad(old,14);
 end;

 // usun z ciagu znaki '()' lub '[]' i przepisz do 'OP_'
  op_:=op_+zm[1];
  zm:=copy(tmp,2,length(tmp)-2);
  j:=1;
 end;

 tmp:=get_dat_noSPC(j,zm,a,',');

//piss

// teraz jesli wystapi znak inny niz ',' to BLAD
 case op of
  '#','<','>','@','^': test_eol(j,zm,a,#0);
 else
  test_eol(j,zm,a,',');
 end;


// przepisz znak nastepujacy po ',' do 'OP_', jesli jest to 'XYS'
// w przeciwnym wypadku wylicz wartosc po przecinku
 if zm[j]=',' then

  if mvnmvp then begin
//   inc(j);
   __inc(j,zm);
   str:=get_dat(j,zm,' ',true);
   war_roz:=oblicz_wartosc(str,a);
   op_:=op_+value_code(war_roz,a,true);

  end else begin

  __inc(j,zm);

   if test_param(j,zm) then begin Result.l:=__nill; exit end else
   if UpCase(zm[j]) in ['X','Y','S'] then begin
    op_:=op_+UpCase(zm[j]);

    if zm[j+1] in ['+','-'] then begin
     if _eol(zm[j+2]) then begin

      if UpCase(zm[j])='S' then blad(old,4);      // + - nie moze byc dla 'S'

      incdec:=true;

       case zm[j+1] of
        '-': //war_roz:=oblicz_wartosc('{de'+zm[j]+'}',a);
             if UpCase(zm[j])='X' then war_roz:=$CA else war_roz:=$88;   // dex, dey
        '+': //war_roz:=oblicz_wartosc('{in'+zm[j]+'}',a);
             if UpCase(zm[j])='X' then war_roz:=$E8 else war_roz:=$C8;   // inx, iny
       end;

      inc(j,2);
     end else begin
      zwieksz:=true; inc(j);
      war_roz:=oblicz_wartosc_noSPC(zm,a,j,#0,'F');
     end;

    end else inc(j);

   end else blad(old,14);
  end;

//  end;
  test_eol(j,zm,a,#0);
 end;


 // jesli to rozkaz skoku lub PEA, PEI, PER to nie relokujemy (BRANCH=TRUE)
 if ( (mnemo[1]='B') and (mnemo[2]<>'I') ) or ( (mnemo[1]='P') and (mnemo[2]='E') and (op_='') and (op=' ') ) then begin
  branch:=true;

  branch_run:=true;
 end else
  branch_run:=false;


 if adres<0 then
  if pass=pass_end then blad(old,10);        // adres<0 na pewno nie bylo ORG'a


// oblicz wartosc argumentu mnemonika, jesli brak argumentu to 'WAR=0'

 war:=0;
 if not((tmp='') and (op='#')) then
  if op<>'@' then war:=oblicz_wartosc(tmp,old);


 if zwieksz then inc(war, war_roz); //war:=war+war_roz;

 op_:=op_+value_code(war,a,true);

 if mvnmvp then war:=war_roz + byte(war) shl 8;


(*----------------------------------------------------------------------------*)
(* wyjatki dotycza skokow warunkowych B?? (6502) ; BRA, BRL, PEA (65816)      *)
(*----------------------------------------------------------------------------*)

 if branch_run then begin

   op_:='B';

   if siz<>' ' then
    if siz='Q' then op_:='W' else
     if siz<>'Z' then blad(old,31);

   j:=adrMode(op_);                  // dowiemy sie ktory to tryb adresowania

   war:=war-2-adres;


   if tryb and maska[j]=2 then

     idx:=128

   else begin

     op_:='W';

     if siz<>' ' then
      if siz<>'Q' then blad(old,31);

     dec(war);

     idx:=65536;

   end;


   test:=false;

   if (war<0) and (abs(war)-idx>0) then begin war:=abs(war)-idx; test:=true end;

   if (war>0) and (war-idx+1>0) then begin war:=war-idx+1; test:=true end;

   if (pass=pass_end) and test then blad(old,integer(-war));
 end;


 // na podstawie 'OP' okresl adresacje 'OP_'
 case op of
  '#','<','>','^': op_:='#';
              '@': op_:='@';
 end;


// znajdz obliczona adresacje w tablicy 'adresacja'
// oraz sprawdz czy dla tego mnemonika jest mozliwa ta adresacja
//
// jesli nie znalazl to zmien rodzaj argumentu Z->Q

 // jesli 65816 to wstaw znak '~'
 if (opt and opt_C>0) then op_:='~'+op_;

 len:=length(op_);


// jesli rozkaz relokowalny (RELOC=TRUE) wymus rozmiar 'Q'
 if reloc and not(dreloc.use) then
  if siz='T' then blad(old,12) else
   if not(op in ['<','>','^']) then siz:='Q';


// jesli wystapila etykieta external (EXT_USED.USE=TRUE) wymus rozmiar EXT_USED.SIZ
 if ext_used.use and (ext_used.siz in ['B','W','L']) then begin

  if op='^' then blad(old,85);

  if op in ['<','>'] then begin

   if not(dreloc.use) and not(dreloc.sdx) then blad(old,58);    // dla Atari-DOS nie ma relokowalych lo, hi

   t_ext[ext_idx-1].typ:=op;
   ext_used.siz:='B';

   if op='>' then t_ext[ext_idx-1].lsb := byte(war);
  end;


  case ext_used.siz of
   'B': siz:='Z';
   'W': siz:='Q';
   'L': siz:='T';
  end;

 end;


// sprawdz czy wystapilo rozszerzenie mnemonika
// zmodyfikuj wielkosc operandu na podstawie 'SIZ'
 if siz<>' ' then
  case op_[len] of
   'Q': if siz<>'Z' then
         op_[len]:=siz
        else
         if pass=pass_end then blad(old,31);

   'T': if not(siz='T') then
         if pass=pass_end then blad(old,31);

   '#': if siz='T' then
         blad(old,14)
        else
         if (siz='Z') and (abs(war)>$FF) then blad(old,31);

   'Z': op_[len]:=siz;
  end;


 j:=adrMode(op_);

 while (j=0) or (tryb and maska[j]=0) do begin

  case op_[len] of		// zmien rozmiar operandu
   'Z': op_[len]:='Q';
   'Q': op_[len]:='T';
  else

   if pass=pass_end then
    blad(old,14)
   else
    Break;

  end;
				// sprawdz czy nowy operand nie kloci sie z zadeklarowanym rozmiarem
  if (siz<>' ') and (pass=pass_end) then
   if not(siz=op_[len]) then blad(old,31);

  j:=adrMode(op_);		// sprawdz czy dla nowego rozmiaru operandu istnieje tryb adresowania
 end;


 if (k=116) and (j=4) then code:=$78;	// wyjatek dla DOP #xx     ($80)
 if (k=111) and (j=10) then code:=$87;	// wyjatek dla SHA abs,y   ($9f)
 if (k=101) and (j=1) then code:=$a3;	// wyjatek dla LAX (zp,x)


 if (k=11) and (j=11) then		// wyjatek dla JML -> JMP
  if (war shr 16) = (adres shr 16) then begin code:=$4c; j:=10; op_:='~Q' end;

// writeln(mnemo,',',k,',',op_,',',j,',',hex(adres,4),' / ',hex(war,4));


// zmienna K bezpieczna, nie została zmodyfikowana do tego miejsca

 if opt and opt_C>0 then begin
  ile:=0;
  for k:=8 downto 1 do
   if ((tryb shr 24) and maska[k]>0) then ile:=byte( (9-k)*23 );

{  if tryb and $80000000>0 then ile:=23;
  if tryb and $40000000>0 then ile:=2*23;
  if tryb and $20000000>0 then ile:=3*23;
  if tryb and $10000000>0 then ile:=4*23;
  if tryb and $08000000>0 then ile:=5*23;
  if tryb and $04000000>0 then ile:=6*23;
  if tryb and $02000000>0 then ile:=7*23;
  if tryb and $01000000>0 then ile:=8*23;}

  inc(code, addycja_16[j+ile])		//code:=byte( code+addycja_16[j+ile] )

 end else
  if (tryb and $80000000>0) then inc(code, addycja[j+12]) else	//code:=code+addycja[j+12]
   if (tryb and $40000000>0) then inc(code, addycja[j+24]) else	//code:=code+addycja[j+24]
    if (tryb and $20000000>0) then inc(code, addycja[j+36]) else//code:=code+addycja[j+36]
     inc(code, addycja[j]);					//code:=code+addycja[j];


// obliczenie wartosci 'WAR' na podstawie 'OP'
// WAR moze byc dowolna wartoscia typu D-WORD

 help:=war;
 if dreloc.use and rel_used then dec(help,rel_ofs);

 case op of
  '<': war := byte( wartosc(a,help,'D') );
  '>': begin war := byte( wartosc(a,help,'D') shr 8 );  _sizm( byte(help) ) end;
  '^': begin war := byte( wartosc(a,help,'D') shr 16 ); _sizm( byte(help) ) end;
 end;


  if (longa or longi <> 0) and macro_rept_if_test then		// LONGA | LONGI
   if not (code in [$f4,$02,ord(REP),ord(SEP)]) then begin	// PEA #, COP #, REP #, SEP #

  // sprawdzamy rozmiar rejestrow dla trybu adresowania natychmiastowego '#'
    if op_[len]='#' then
     case mnemo[3] of
      'A','C','D','P','R','T':		// lda, adc, sbc, and, cmp, ror, bit

        if longa > 0 then
	 if longa = 8 then begin
	   if siz='Q' then blad(old, 63);
	   siz:='Z';
	 end else
	   siz:='Q';

	  //test_reg_size(a,asize,ile, longa);

      'X','Y':				// ldx, ldy, cpx, cpy,

        if longi > 0 then
	 if longi = 8 then begin
	   if siz='Q' then blad(old, 63);
	   siz:='Z';
	 end else
	  siz:='Q';

     end;

  end;


// policz z ilu bajtow sklada sie rozkaz wraz z argumentem
 ile:=1;

 if not(mvnmvp) then
  if incdec then begin
   inc(ile);
   case op_[len] of
    'Z': war := (war and $ff) or byte(war_roz) shl 8;
    'Q': war := (war and $ffff) or byte(war_roz) shl 16;
    'T': war := (war and $ffffff) or byte(war_roz) shl 24;
   end;
  end;

 if op_='~ZZ' then inc(ile,2)
 else
  case op_[len] of
   '#': begin
         if siz=' ' then siz:=value_code(war,a,false);

         case siz of
          'Z': begin
                war:=wartosc(a,war,'B');
                inc(ile)
               end;

          'Q': if (opt and opt_C=0) then
                blad(old,0,'('+IntToStr(war)+' must be between 0 and 255)')
               else begin
                war:=wartosc(a,war,'A');
                inc(ile,2)
               end;
         end;

        end;
   'Z','B': inc(ile);
   'Q','W': inc(ile,2);
   'T': inc(ile,3);
  end;


// okreslamy rozmiar relokowalnego argumentu B,W,L,<,>
 if dreloc.use and rel_used then begin

  case op_[len] of
       '#': if (op in ['<','>','^']) then dreloc.siz:=op;
   'Z','B': dreloc.siz:=relType[1];
   'Q','W': dreloc.siz:=relType[2];
       'T': dreloc.siz:=relType[3];
   end;

  if not(ext_used.use) then dec(war,rel_ofs);  // nie wolno modyfikowac argumentu symbolu EXTERNAL

  _siz(true);

  rel_used:=false;
 end;


 // tutaj przeprowadzamy operacje sledzenia rozmiaru rejestrow A,X,Y
 // modyfikowanych przez rozkazy REP, SEP
  if (opt and opt_T>0) and (pass=pass_end) and macro_rept_if_test then begin  // wlaczona opcja sledzenia rozkazow SEP, REP

   if code in [ord(REP), ord(SEP)] then reg_size( byte(war), t_MXinst(code));

//   if mSEP then reg_size( byte(war),true ) else
//    if mREP then reg_size( byte(war),false );

  // sprawdzamy rozmiar rejestrow dla trybu adresowania natychmiastowego '#'
   if not(pomin) then
    if op_[len]='#' then
     case mnemo[3] of
      'A','C','D','P','R','T': test_reg_size(a,asize,ile, longa);	// lda, adc, sbc, and, cmp, ror, bit
        	      'X','Y': test_reg_size(a,isize,ile, longi);	// ldx, ldy, cpx, cpy
     end;

  end;


 // sprawdzamy atrybut etykiet

 if pass=pass_end then
  case attribute.atr of
  // READ
   __R: if code in [$0e,$06,$1e,$16,$2e,$26,$3e,$36,$4e,$46,$5e,$56,$6e,$66,$7e,$76,$ce,$c6,$de,$d6,$ee,$e6,$fe,$f6,$8d,$85,$9d,$99,$95,$81,$91,$8e,$86,$96,$8c,$84,$94, $64,$9c] then warning(118);
  // WRITE
   __W: if code in [$6d,$65,$7d,$79,$75,$61,$71,$2d,$25,$3d,$39,$35,$21,$31,$2c,$24,$cd,$c5,$dd,$d9,$d5,$c1,$d1,$ec,$e4,$cc,$c4,$4d,$45,$5d,$59,$55,$41,$51,$6c,$ad,$a5,$bd,$b9,$b5,$a1,$b1,$ae,$a6,$be,$b6,$ac,$a4,$bc,$b4,$0d,$05,$1d,$19,$15,$01,$11,$ed,$e5,$fd,$f9,$f5,$e1,$f1] then warning(118);
  end;


 // preparujemy wynik, rozkaz CPU + argumenty

 Result.l := ile;

 Result.h[0] := code;
 Result.h[1] := byte(war);
 Result.h[2] := byte(war shr 8);
 Result.h[3] := byte(war shr 16);
 Result.h[4] := byte(war shr 24);

 if (Result.h[0]=$6c) and (Result.h[1]=$ff) and (pass=pass_end) then warning(124);

 mne_used := true;           // zostal odczytany jakis mnemonik

end;


function reserved(var ety: string): Boolean;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var v: byte;
begin
  v:=fASC(ety);

  Result := (v in [$80..$9f]);	// PSEUDO
  if Result then exit;

  if opt and opt_C>0 then
   Result := (v in [1..92])	// 65816
  else
   Result := (v in [1..56]);	// 6502

end;


procedure reserved_word(var ety, zm: string);
(*----------------------------------------------------------------------------*)
(*  testuj czy nie zostala uzyta zarezerwowana nazwa, np. nazwa pseudorozkazu *)
(*  lub czy nazwa zostala juz wczesniej uzyta                                 *)
(*----------------------------------------------------------------------------*)
begin

  if ety[1]='?' then warning(8);

  if length(ety)=3 then
   if reserved(ety) then blad_und(zm,ety,9);

  if rept then blad(zm,51);
  //if skip and proc then blad(zm,17);

  if load_lab(ety,true) >= 0 then blad_und(zm,ety,2);        // nazwa w uzyciu

end;


procedure create_struct_variable(var zm,ety: string; var mne: int5; const head: Boolean; var adres: integer);
(*----------------------------------------------------------------------------*)
(*  wykonaj .STRUCT (np. deklaracja pola struktury za pomoca innej struktury) *)
(*  możliwe jest przypisanie pol zdefiniowanych przez strukture nowej zmiennej*)
(*----------------------------------------------------------------------------*)
var indeks, _doo, j, k, idx, hlp: integer;
    txt, str: string;
begin

    indeks:=mne.i;

    if mne.l=__enum_run then begin

     save_lst('a');

     save_nul(indeks);
     inc(adres, indeks);

     exit;
    end;

  // sprawdzamy czy struktura nie wywoluje sama siebie
    if t_str[indeks].lab+'.'=lokal_name then blad(zm,57);

     _doo := adres-struct.adres;

     if mne.l=__struct_run then
      if struct.use then
       save_lab(ety, _doo, bank, zm)     // nowe pole w strukturze
      else
       save_lab(ety, adres, bank, zm);   // definicja zmiennej typu strukturalnego

     save_lst('a');

   // odczytujemy liczbe pol struktury
     hlp:=t_str[indeks].ofs;
     inc(indeks);

     for idx:=indeks to indeks+hlp-1 do begin

      txt:=t_str[idx].lab;

      if mne.l=__struct_run_noLabel then
       str:=ety+'.'+txt
      else begin

       //_odd:=pos('.',txt);                                //???
       //if _odd>0 then txt:=copy(txt,_odd,length(txt));    //???

       if txt[1]<>'.' then txt:='.'+txt;

       str:=ety+txt;
      end;

      j:=t_str[idx].siz;

      if struct.use then begin
       k:=t_str[idx].ofs+_doo;                   // konieczna operacja, bo STRUCT.ADRES nie zostal zwiekszony

       save_str(str,k,j,1,adres,bank);           // tutaj zwiekszony zostaje STRUCT.ADRES

       save_lab(str,adres-struct.adres,bank,zm); // tutaj operujemy na nowej wartosci STRUCT.ADRES

       inc(struct.cnt);                          // zwiekszamy licznik pol w strukturze
      end else begin

       save_lab(str,adres, bank,zm);

       if dreloc.use or dreloc.sdx then
        save_nul(j*t_str[idx].rpt)
       else
        if head then new_DOS_header;             // wymuszamy zapis naglowka DOS-a

      end;

      inc(adres, j*t_str[idx].rpt);
     end;

end;


procedure create_struct_data(var i: integer; var zm, ety: string; v: byte);
(*----------------------------------------------------------------------------*)
(* dla   DTA STRUCT_NAME [EXPRESSION]   tworzymy dane typu strukturalnego     *)
(*----------------------------------------------------------------------------*)
var _doo, _odd, k, idx: integer;
    war: Int64;
    tmp: string;
begin
           struct_used.use:=false;

           _odd:=adres; war:=adres;
           _doo:=bank;

           k:=bank;

           save_lst('a');

           if v>=__byte then
            dec(v, __byteValue)
           else
            v:=1;

           test_skipa;

           oblicz_dane(i,zm,zm,v);

       // jesli stworzylismy strukture to odpowiednio zapamietaj
       // jej dane, adres, stworzyciela itp.
           if struct_used.use then begin

            if ety='' then blad(zm,15);
            if (pass<2) and (ety[1]='?') then warning(8);


            idx:=load_lab(ety,true);


       // jesli etykieta byla juz zadeklarowana i to jest PASS=0
       // tzn ze mamy blad LABEL DECLARED TWICE
            if (pass=0) and (idx>=0) then blad_und(zm,ety,2);


            _doo:=__dta_struct;

            if t_lab[idx].bnk=__dta_struct then begin
         // wystapila juz ta deklaracja danych strukturalnych
             _odd:=t_lab[idx].adr;

             t_str[_odd].adr := cardinal( war );
             t_str[_odd].bnk := integer( k );

            end else begin

         // w TMP tworzymy nazwe uwzgledniającą lokalnosc 'TMP:= ??? + ETY'
             if run_macro then tmp:=macro_nr+{lokal_name+}ety else
              if proc then tmp:=proc_name+lokal_name+ety else
               tmp:=lokal_name+ety;

         // nie wystapila jeszcze ta deklaracja danych strukturalnych
             save_str(tmp,struct_used.cnt,0,1, integer(war), integer(k));

             _odd:=loa_str(tmp, struct.id);

             t_str[_odd].idx:=struct_used.idx;
            end;

           end;

           save_lab(ety,cardinal(_odd),integer(_doo),zm);     // zapisujemy etykiete normalnie poza strukturą
end;


procedure oddaj_var;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var i, y, x, k, idx: integer;
    txt, tmp: string;
    old_run_macro: Boolean;
    mne: int5;
begin

if var_idx>0 then begin

 old_run_macro := run_macro;
 run_macro     := false;

 tmp:='';

 for i:=0 to var_idx-1 do
  if (t_var[i].lok = end_idx) and (t_var[i].exc) then begin   // zmienne odkladamy w odpowiednim obszarze lokalnym

   txt := t_var[i].nam;                  // nazwa zmiennej .VAR

   if t_var[i].adr>=0 then               // zmienne .VAR z okreslonym adresem umiejscowienia
    nul.i:=t_var[i].adr
   else
    nul.i:=adres;                        // zmienne .VAR alokowane dynamicznie

   if nul.i<0 then blad(global_name,87); // Undefined variable address

   save_lst('l');

   case t_var[i].typ of
    'V': begin
          save_lab(txt,nul.i,bank,txt);

          if t_var[i].adr<0 then         // T_VAR[I].ADR<0 oznacza brak okreslonej wartosci
           for y:=t_var[i].cnt-1 downto 0 do save_dta(t_var[i].war , tmp , tType[t_var[i].siz] , 0);
         end;

    'S': begin
          y:=load_lab(t_var[i].str, false);

          mne.i:=t_lab[y].adr;           // znajdz indeks do struktury
          mne.l:=byte(__struct_run);

          if t_var[i].cnt>1 then begin

           idx:=adres;
           if t_var[i].adr>=0 then adres:=t_var[i].adr;

           tmp:=t_var[i].str+'['+IntToStr(t_var[i].cnt)+']';

           k:=1;
           create_struct_data(k,tmp,txt, mne.l);

           adres:=idx;

          end else
           if t_var[i].zpv or (t_var[i].adr>=0) then begin  // jesli .ZPVAR lub okreslony adres
            x:=t_var[i].adr;
            create_struct_variable(txt, txt, mne, false, x);
           end else
            create_struct_variable(txt, txt, mne, true, adres);

         end;
   end;

   tmp:=txt; zapisz_lst(txt);

   t_var[i].lok:=-1;

  end;

 nul.i:=0;
 save_lst(' ');                          // koniecznie musi to tutaj byc

 run_macro := old_run_macro;

end;

end;


procedure add_blok(var a: string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 inc(blok);
 if blok>$FF then blad(a,45);
end;


procedure save_blk(const kod:integer; var a:string; const h:Boolean);
(*----------------------------------------------------------------------------*)
(*  BLK UPDATE ADDRESS                                                        *)
(*----------------------------------------------------------------------------*)
var x, y, i, j, k: integer;
    hea_fd, hea_fe, ok, tst: Boolean;
    txt: string;
begin
 txt:=a;

 for k:=blok downto 0 do begin

  hea_fd:=false; ok:=false;

// szukaj w glownym bloku

  for y:=0 to rel_idx-1 do
  if t_rel[y].idx=kod then
   if t_rel[y].blo=0 then
    if t_rel[y].blk=k then begin

     if not(hea_fd) then begin
      if h then begin
       save_lst('a');

       save_dstW( $fffd );
       save_dst( byte(K) );
       save_dstW( $0000 );

       zapisz_lst(txt);
      end;

      hea_fd:=true; ok:=true;
     end;

     save_lst('a');

     save_dst($fd);
     save_dstW( t_rel[y].adr );   // save_dst(byte(t_rel[y].adr shr 8));

     zapisz_lst(txt);

     t_rel[y].idx:=-100;      // wylacz z poszukiwan
    end;

// szukaj w blokach relokowalnych
  for x:=1 to blok do begin

  hea_fe:=false; j:=0; tst:=false;

  for y:=0 to rel_idx-1 do
  if t_rel[y].idx=kod then
   if t_rel[y].blo=x then
    if t_rel[y].blk=k then begin

     if not(tst) then begin
      save_lst('a');
      tst:=true;
     end;

     if not(hea_fe) then begin
      if not(hea_fd) and h then begin
       save_dstW( $fffd );
       save_dst( byte(K) );
       save_dstW( $0000 );

       hea_fd:=true;
      end;

      save_dst($fe);
      save_dst(byte(x));

      hea_fe:=true; ok:=true;
     end;

     j:=t_rel[y].adr-j;
     if j>=$fa then
      for i:=0 to (j div $fa)-1 do begin
       save_dst($ff);
       dec(j,$fa);
      end;

     save_dst(byte(j));
     j:=t_rel[y].adr;

     t_rel[y].idx:=-100;      // wylacz z poszukiwan
    end;

   if tst then zapisz_lst(txt);
  end;

  if ok then begin
   save_lst('a');

   save_dst($fc);

   zapisz_lst(txt);
  end;

 end;

end;


function get_pubType(var txt,zm:string; var _odd:integer): byte;
(*----------------------------------------------------------------------------*)
(* odczytujemy typ etykiety public, _ODD = indeks do etykiety w tablicy T_LAB *)
(*----------------------------------------------------------------------------*)
begin

  Result:=0;

  _odd:=load_lab(txt,false);

  if _odd<0 then blad_und(zm,txt,73);

// symbolami publicznymi nie moga byc etykiety przypisane do
// SMB, STRUCT, PARAM, EXT, MACRO

  if t_lab[_odd].bnk>=__id_param then begin
   Result := byte( t_lab[_odd].bnk );
   if not( Result in [__proc_run, __array_run, __struct_run]) then blad_und(zm,txt,103);
  end;

end;


function get_smb(var i:integer; var zm:string): string;
(*----------------------------------------------------------------------------*)
(*  pobieramy 8 znakowy symbol SMB                                            *)
(*----------------------------------------------------------------------------*)
var txt: string;
    x: integer;
begin
 txt:=get_string(i,zm,zm,true);

 if length(txt)>8 then blad(zm,44);        // za dluga nazwa etykiety

 while length(txt)<8 do txt:=txt+' ';      // wyrownaj do 8 znakow

 for x:=1 to 8 do txt[x]:=UpCase(txt[x]);

 Result:=txt;
end;


procedure blk_update_new(var i:integer; var zm:string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var txt, str: string;
    war, k: integer;
begin
 txt:=zm; zapisz_lst(txt); str:='';

 omin_spacje(i,zm);
 txt:=get_dat(i,zm,' ',true); if txt='' then blad(zm,23);


 if test_symbols then
  for war:=High(t_sym)-1 downto 0 do
   if txt=t_sym[war] then begin blad_und(zm,txt,2); exit end;


 war:=l_lab(txt); if war<0 then blad_und(zm,txt,5);
 k:=t_lab[war].blk; if k=0 then blad(zm,53);

 save_lst('a');

// dta a($fffc),b(blk_num),a(smb_off)
// dta c'SMB_NAME'
 save_dstW( $fffc );
 save_dst(byte(k));
 save_dstW( t_lab[war].adr );  // save_dst(byte(t_lab[war].adr shr 8));

 zapisz_lst(str);
 save_lst('a');

 txt:=get_smb(i,zm);
 for k:=1 to 8 do save_dst( ord(txt[k]) );

 zapisz_lst(txt);
 bez_lst:=true;
end;


procedure oddaj_sym;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var txt: string;
    i, k: integer;
begin

if sym_idx>0 then begin

 if adres<0 then blad(global_name,10);

 test_symbols := false;

 for i:=sym_idx-1 downto 0 do begin
 // preparujemy linie dla NEW SYMBOL
  txt:='BLK UPDATE NEW ' + t_sym[i] + ' ' + '''' + t_sym[i] + '''';

  save_lst('a');

  k:=16;  blk_update_new(k,txt);
 end;

end;

end;


procedure blk_empty(const idx: integer; var zm: string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var indeks, tst: cardinal;
    _doo: integer;
    txt: string;
begin

 txt:=zm;
 save_lst('a');

 add_blok(zm);

// a($fffe),b(blk_num),b(blk_id)
// a(blk_off),a(blk_len)
 save_dstW( $fffe );
 save_dst(byte(blok));
 save_dst(memType or $80);

 save_dstW( adres ); //save_dst(byte(adres shr 8));
 save_dstW( idx );   //save_dst(byte(idx shr 8));

// jesli deklaracja etykiet wystapila przed blokiem EMPTY
// znajdz je i popraw im numer bloku
 indeks:=adres; tst:=adres+idx;

 for _doo:=0 to High(t_lab)-1 do
  if (t_lab[_doo].adr>=indeks) and (t_lab[_doo].adr<=tst) then
   t_lab[_doo].blk:=blok;

 zapisz_lst(txt);
 bez_lst:=true;
end;


procedure oddaj_ds;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var zm, txt: string;
begin

 if ds_empty>0 then begin
  dec(adres, ds_empty);
  zm:='BLK EMPTY';

  if dreloc.sdx then              // dreloc.sdx BLOK EMPTY
   blk_empty(ds_empty, zm)
  else begin                      // dreloc.use BLOK EMPTY
   save_lst('a');

   save_dstW( __hea_address );
   save_dst( byte('E') );
   save_dstW( 1 );                // word(adres - rel_ofs) );
   save_dstW( ds_empty );

   txt:=zm; zapisz_lst(txt);
  end;

  save_hea;
  inc(adres, ds_empty);

  ds_empty:=0;
 end;

end;


procedure blk_update_symbol(var zm:string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var txt: string;
    k: byte;
    _doo: integer;
begin

 if smb_idx>0 then begin

             txt:=zm; zapisz_lst(txt);

             for _doo:=0 to smb_idx-1 do
              if t_smb[_doo].use then begin

              save_lst('a');

            // a($fffb),c'SMB_NAME',a(blk_len)
              save_dstW( $fffb );

              txt:=t_smb[_doo].smb;
              for k:=1 to 7 do save_dst( ord(txt[k]) );
	      if t_smb[_doo].weak then
               save_dst( ord(txt[8]) or $80 )
              else
               save_dst( ord(txt[8]) );

              save_dstW( $0000 );

              zapisz_lst(txt);

              save_blk(_doo,txt,false);
             end;

             bez_lst:=true;
//             smb_idx:=0;
 end;

end;


procedure blk_update_address(var zm:string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var txt: string;
    idx, i, _odd: integer;
    v: byte;
    ch: Boolean;
begin
            if not(dreloc.use) then

             save_blk(-1,zm,true)      // dla bloku Sparta DOS X

            else begin

             txt:=zm; zapisz_lst(txt);

            // naglowek $FFEF, typ, liczba adresow, adresy

{
  if rel_idx>0 then begin
   Writeln(rel_idx);
   for i:=0 to rel_idx-1 do
    Writeln(hex(t_rel[i].adr,4),',',t_rel[i].bnk,',',t_siz[t_rel[i].idx].siz,',',t_rel[i].idx,',',hex(t_siz[t_rel[i].idx].lsb,2));
  end;
}

             for i:=1 to length(relType) do begin       // dostepne typy B,W,L,D,<,>,^

              ch:=false;
              for idx:=0 to rel_idx-1 do
               if t_siz[t_rel[idx].idx].siz=relType[i] then begin ch:=true; Break end;

              if ch then begin

              save_lst('a');

            // A(HEADER = $FFEF)
              save_dstW( __hea_address );

            // najpierw zapiszemy do bufora aby dowiedziec sie ile ich jest
            // maksymalnie mozemy zapisac $FFFF adresow
              _odd:=0;
//              old_case:=false;                           // jesli bank=0 to FALSE
              for idx:=0 to rel_idx-1 do
               if t_siz[t_rel[idx].idx].siz=relType[i] then begin

//                if t_rel[idx].bnk>0 then old_case:=true; // jesli bank>0 to TRUE

                t_tmp[_odd] := (cardinal(t_rel[idx].adr) and $FFFF) or (t_siz[t_rel[idx].idx].lsb shl 16);

                inc(_odd);
                testRange(zm, _odd, 13);    // koniecznie blad 13 aby natychmiast zatrzymac
               end;

              v:=ord(relType[i]);  //if old_case then v:=v or $80;

              save_dst(v);                 // TYPE //+ MODE

              zapisz_lst(txt);
              save_lst('a');

             // zapisujemy informacje o liczbie adresow  DATA_LENGTH
              save_dstW( _odd );

            // teraz zapisujemy informacje o adresach

              for idx:=0 to _odd-1 do begin
              // bank etykiety external jesli MODE=1
//               if old_case then save_dst( byte(t_tmp[idx] shr 16) );

              // adres do relokacji
               save_dstW( t_tmp[idx] );


               case relType[i] of
                '>': save_dst( byte(t_tmp[idx] shr 16) );
                '^': blad(zm,27);
               end;

              end;

              zapisz_lst(txt);

              end; //if ch then begin

             end;

            end;

            bez_lst:=true;
            first_org:=true;
end;


procedure blk_update_external(var zm:string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var txt: string;
    idx, _doo, _odd, i: integer;
    v: byte;
    ch: Boolean;

const
    typExt: array [0..2] of char = (#0,'<','>');

begin

 if dreloc.sdx then exit;

 //if not(dreloc.use) then blad(zm,53);   <- możliwosc wygenerowania bloku BLK UPDATE EXTRN
 //                                       <- dla plikow innych niz relokowalne

 if extn_idx>0 then begin

             txt:=zm; zapisz_lst(txt);
             save_lst('a');

{
   Writeln(ext_idx);
   for i:=0 to ext_idx-1 do
    Writeln(hex(t_ext[i].adr,4),',',t_extn[t_ext[i].idx].nam);
}

             for _doo:=0 to extn_idx-1 do begin

              for i:=0 to 2 do begin

              ch:=false;
              for idx:=0 to ext_idx-1 do
               if (t_ext[idx].idx=_doo) and (t_ext[idx].typ=typExt[i]) then begin ch:=true; Break end;

              if ch then begin     // czy wystapily w programie odwolania do etykiet external

              save_lst('a');

            // A(HEADER = $FFEE),b(TYPE)
              save_dstW( __hea_external );

            // najpierw zapiszemy do bufora aby dowiedziec sie ile ich jest
            // maksymalnie mozemy zapisac $FFFF adresow i ich numerow bankow
              _odd:=0;
//              old_case:=false;                          // jesli bank=0 to FALSE

              for idx:=0 to ext_idx-1 do
               if (t_ext[idx].idx=_doo) and (t_ext[idx].typ=typExt[i]) then begin

//                if t_ext[idx].bnk>0 then old_case:=true; // jesli bank>0 to TRUE

                t_tmp[_odd] := (t_ext[idx].adr and $FFFF) or (t_ext[idx].lsb shl 16) {(t_ext[idx].bnk shl 16)};

                inc(_odd);
                testRange(zm, _odd, 13);    // koniecznie blad 13 aby natychmiast zatrzymac
               end;

              if typExt[i]=#0 then
               v:=ord(t_extn[_doo].siz)  //if old_case then v:=v or $80;
              else
               v:=ord(typExt[i]);

              save_dst(v);                    // ext_label TYPE //+ MODE

              zapisz_lst(txt);
              save_lst('a');

             // zapisujemy informacje o liczbie adresow
              save_dstW( _odd );

           // A(EXT_LABEL_LENGTH) , C'EXT_LABEL'
              txt:=t_extn[_doo].nam;

              save_dstS(txt);                           // ext_label length, string


            // teraz zapisujemy informacje o adresach

              for idx:=0 to _odd-1 do begin
              // bank etykiety external
//               if old_case then save_dst( byte(t_tmp[idx] shr 16) );

              // adres etykiety external
               save_dstW( t_tmp[idx] );

               if typExt[i]='>' then save_dst( byte(t_tmp[idx] shr 24) );
              end;

              zapisz_lst(txt);

              end; //for i:=0 to 3 do begin

              end; //if ch then begin

             end;

//             extn_idx:=0;
             bez_lst:=true;
 end;
end;


procedure blk_update_public(var zm:string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var txt, ety, str, tmp: string;
    x, idx, j, k, indeks, _odd, _doo, i, len, old_rel_idx, old_siz_idx: integer;
    sid, sno, six: integer;
    v, sv: byte;
    ch, tp: char;
    test: Boolean;
    war: Int64;
    old_sizm0, old_sizm1: rSizTab;
begin

 if dreloc.sdx then exit;

 if pub_idx>0 then begin

             txt:=zm; zapisz_lst(txt);
             save_lst('a');

             _odd:=0;

             _doo:=-1;

           // test obecnosci etykiet publicznych oraz test parametrow procedur __pVar

             for idx:=pub_idx-1 downto 0 do begin
              txt:=t_pub[idx].nam;

              v := get_pubType(txt,zm, _odd);

           // dodajemy do upublicznienia parametry procedury __pVar
           // pod warunkiem ze ich wczesniej jeszcze nie upublicznialismy
              if v = __proc_run then
               if t_prc[t_lab[_odd].adr].typ = __pVar then begin

                k:=t_prc[t_lab[_odd].adr].par;        // liczba parametrow
                indeks:=t_prc[t_lab[_odd].adr].str;

                if k>0 then
                 for j:=0 to k-1 do begin
                  ety:=t_par[j+indeks];

                // omijamy pierwszy znak okreslajacy typ parametru
                // i czytamy az nie napotkamy znakow nie nalezacych do nazwy etykiety

                  str:='';
                  i:=2;
                  len:=length(ety);

                  while i<=len do begin
                   if _lab(ety[i]) then str:=str+ety[i] else Break;
                   inc(i);
                  end;

//                  str:=copy(ety,2,length(ety));    // poprawiamy nazwe parametru

                  _doo:=l_lab(str);

                  test:=false;
                  for x:=pub_idx-1 downto 0 do
                   if t_pub[x].nam=str then begin test:=true; Break end;

                  if (_doo>=0) and not(test) then  // dopisujemy do T_PUB jesli nie zostala wczesniej upubliczniona
                   if (t_lab[_doo].bnk<>__id_ext) {and not(test)} then save_pub(str,zm);

                  end;

                  if _doo<0 then blad_und(zm,str,5);

                 end;

               end;


          // okreslamy typ etykiety PUBLIC, czy jest relokowalna

             branch:=false;       // umożliwiamy relokowalnosc

             old_rel_idx      := rel_idx;
             old_siz_idx      := siz_idx;
             old_sizm0        := t_siz[siz_idx];
             old_sizm1        := t_siz[siz_idx-1];

             for _odd:=pub_idx-1 downto 0 do begin
              txt:=t_pub[_odd].nam;

              reloc:=false;

              oblicz_wartosc(txt,zm);
              t_pub[_odd].typ := reloc;
             end;

             branch:=true;        // blokujemy relokowalnosc

             rel_idx          := old_rel_idx;
             siz_idx          := old_siz_idx;
             t_siz[siz_idx]   := old_sizm0;
             t_siz[siz_idx-1] := old_sizm1;

{
   Writeln(pub_idx);
   for x:=0 to pub_idx-1 do Writeln(t_pub[x].nam,',',t_pub[x].typ);
}


          // A(HEADER = $FFED) , a(LENGTH)
             save_dstW( __hea_public );
             save_dstW( pub_idx );

             for idx:=0 to pub_idx-1 do begin

              txt:=t_pub[idx].nam;

              ety:=txt;
              save_lst('a');

              v := get_pubType(txt,zm, _odd);  // V to typ, _ODD to indeks do T_LAB

              case v of
                 __proc_run: ch:='P';        // P-ROCEDURE
                __array_run: ch:='A';        // A-RRAY
               __struct_run: ch:='S';        // S-TRUCT
              else

               if t_pub[idx].typ then
                ch := 'V'                    // V-ARIABLE
               else
                ch := 'C';                   // C-ONSTANT

              end;

              tp:='W';

              if ch='C' then begin           // type B-YTE, W-ORD, L-ONG, D-WORD
               war:=t_lab[_odd].adr;

               tp:=relType [ ValueToType(war) ];

               save_dst(ord(tp));     // type

              end else
               save_dst( byte('W') ); // type W-ORD dla V-ARIABLE, P-ROCEDURE, A-RRAY, S-TRUCT


              save_dst(ord(ch));      // label_type V-ARIABLE, C-ONSTANT, P-ROCEDURE, A-RRAY, S-TRUCT

              save_dstS(txt);         // label_name     [length + atascii]

              case v of
                  __proc_run: k:=t_prc[t_lab[_odd].adr].adr;    // PROC address
                 __array_run: k:=t_arr[t_lab[_odd].adr].adr;    // ARRAY address
                __struct_run: k:=t_str[t_lab[_odd].adr].ofs;    // liczba pol STRUCT
              else
               k:=t_lab[_odd].adr;              // variable address
              end;

              if not(ch in ['C','S']) then dec(k,rel_ofs);   // wartosci C-ONSTANT i S-TRUCT nie modyfikujemy


              for sv:=1 to TypeToByte(tp) do begin
                                                // wartosc zmiennej, stalej lub procedury
               save_dst( byte(k) );             // o rozmiarze TP (B-YTE, W-ORD, L-ONG, D-WORD)
               k := k shr 8;
              end;


      // S-TRUCT
              if v = __struct_run then begin

               sid:=t_str[t_lab[_odd].adr].id;
               sno:=t_str[t_lab[_odd].adr].ofs;

               for j:=0 to sno-1 do begin
                six:=loa_str_no(sid, j);

                txt:=t_str[six].lab;

                save_dst ( byte( relType[t_str[six].siz] ) );

                save_dstS ( txt );

                save_dstW ( word(t_str[six].rpt) );

               { write(t_str[six].lab);       // nazwa struktury
                write(',',t_str[six].ofs);   // ofset lub liczba pol struktury
                write(',',t_str[six].siz);   // dlugosc calkowita w bajtach

                write(',',hex(t_str[six].rpt,4));

                writeln(',',t_str[six].no); }
               end;

              end else

      // A-RRAY
              if v = __array_run then begin

               save_dstW( t_arr[t_lab[_odd].adr].elm[0].cnt );  // maksymalny indeks tablicy

               save_dst( ord ( relType[t_arr[t_lab[_odd].adr].siz] ) );   // rozmiar pol

              end else

      // P-ROCEDURE
              if v = __proc_run then begin
               k:=t_prc[t_lab[_odd].adr].reg;
               save_dst( byte(k) );             // kolejnosc rejestrow

               ch:=t_prc[t_lab[_odd].adr].typ;
               save_dst( ord(ch) );             // typ procedury ' '__pDef, 'R'__pReg, 'V'__pVar


               k:=t_prc[t_lab[_odd].adr].par;   // liczba parametrow

               indeks:=t_prc[t_lab[_odd].adr].str;


               if (k>0) and (ch=__pVar) then    // jesli __pVar to wliczamy tez dlugosc
                for j:=0 to k-1 do begin        // nazw pametrow
                 tmp:=t_par[j+indeks];
                 inc(k,length(tmp)+2-1);
                end;

               save_dstW( k );                  // liczba danych na temat parametrow


               k:=t_prc[t_lab[_odd].adr].par;   // liczba parametrow jeszcze raz


               if k>0 then                      // jesli sa parametry to je zapiszemy
                for j:=0 to k-1 do begin
                 tmp:=t_par[j+indeks];
                 save_dst(ord(tmp[1]));

                 if ch=__pVar then begin        // dodatkowo dlugosc i nazwe etykiety jesli to __pVar
                  txt:=copy(tmp,2,length(tmp)); // omijamy pierwszy znak typu

                  save_dstS( txt );
                 end;

                end;

              end;

              zapisz_lst(ety);
             end;

             bez_lst:=true;
 end;
end;


procedure operator_zlozony(var i:integer; var zm,ety:string; const glob:Boolean);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var txt: string;
begin

 if ety[1]<>'?' then blad(zm,58); // te operacje dotycza etykiet tymczasowych

 if glob then
  txt:=':'
 else
  txt:='';

 txt:=txt+ety+zm[i];

 if if_test then
  if zm[i+1]='=' then begin
    insert(txt,zm,i+2);      // modyfikujemy linie np. ?tmp+=3 -> ?tmp=?tmp+3
    delete(zm,i,1)
  end else begin
   test_eol(i+2,zm,zm,#0);

   zm:=ety+'='+txt+'1';     // modyfikujemy linie  ?tmp++ -> ?tmp=?tmp+1
   i:=length(ety)+1;        // modyfikujemy linie  ?tmp-- -> ?tmp=?tmp-1
  end;

end;


procedure get_data_array(var i:integer; var zm:string; const idx:integer);
(*----------------------------------------------------------------------------*)
(*  zapisanie elementu do tablicy .ARRAY                                      *)
(*----------------------------------------------------------------------------*)
var ety, str: string;
    k, j, _odd: integer;
    typ: byte;
begin

 save_lst(' ');

 omin_spacje(i,zm);

 if not(zm[i] in AllowStringBrackets) then begin

  ety:='['+IntToStr(array_used.max)+']';

  if zm[i]='=' then __inc(i,zm);

 end else begin

  ety:=get_dat_noSPC(i,zm,zm,'=');
  if ety='' then ety:='[0]';

  if zm[i]<>'=' then
   blad(zm,58)
  else
   __inc(i,zm);

 end;

 str:=get_dat_noSPC(i,zm,zm,'\');

 typ:=t_arr[idx].siz;

 k:=1;

 while true do begin

  _odd:=read_elements(k,ety, idx, false);

  array_used.idx:=_odd div typ;
  array_used.typ:=tType[ typ ];

  if not(loop_used) and not(FOX_ripit) and (length(t)+7<margin) then t:=t+' ['+hex(cardinal(_odd),4)+']';

  j:=1; oblicz_dane(j,str,zm, typ);

  omin_spacje(k,ety);
  if ety[k]<>':' then Break else __inc(k,ety);

 end;

 if k<=length(ety) then blad(zm,8,ety[k]);

end;


procedure add_proc_nr;
(*----------------------------------------------------------------------------*)
(*  zwiekszamy licznik PROC_IDX a przez to i PROC_NR                          *)
(*----------------------------------------------------------------------------*)
begin
 inc(proc_idx);

 proc_nr:=proc_idx;     // PROC_IDX to pierwszy wolny wpis do T_PRC
                        // kazdy nowy blok .PROC musi otrzymac nowy niepowtarzalny numer

 if proc_idx>High(t_prc) then SetLength(t_prc, proc_idx+1);
end;


procedure upd_procedure(var ety,zm:string; const a:integer);
(*----------------------------------------------------------------------------*)
(*  uaktualniamy wartosc BANK, ADRES i parametry procedury typu ' '           *)
(*----------------------------------------------------------------------------*)
var str, txt, b, tmp, add: string;
    _doo, _odd, idx, i, len: integer;
    tst: cardinal;
    old_bool, old_macro: Boolean;
begin

   t_prc[proc_nr].bnk:=bank;
   t_prc[proc_nr].adr:=a;

   t_prc[proc_nr].ofs:=org_ofset;

   str:=lokal_name+ety;
   zapisz_etykiete(str,a,bank,ety[1]);

   old_macro  := run_macro;
   run_macro  := false;

   old_bool   := dreloc.use;   // aby parametry procedury nie byly relokowalne
   dreloc.use := false;

   _doo:=t_prc[proc_nr].par;    // liczba zadeklarowanych parametrow w aktualnej procedurze

   if _doo>0 then
    case t_prc[proc_nr].typ of

   __pDef: begin

          // jesli procedura miala zadeklarowane parametry to
          // odczytamy adres dla parametrow zawarty w @PROC_VARS_ADR
          // i zaktualizujemy adresy parametrow procedury

            tst:=adr_label(__PROC_VARS_ADR, true);   // @proc_vars_adr

            proc:=true;                  // PROC=TRUE i PROC_NAME
            proc_name:=ety+'.';          // umozliwia uaktualnienie adresow etykiet

          // wymus wykonanie makr @PULL 'I'

//             wymus_zapis_lst(zm);

             zm:=' @PULL ''I'','+IntToStr(t_prc[proc_nr].ile);

             idx:=t_prc[proc_nr].str;

             for _odd:=0 to _doo-1 do begin   // !!! koniecznie taka kolejnosc petli FOR !!!
              txt:=t_par[idx+_odd];
              str:=copy(txt,2,length(txt));

          // uaktualnimy adresy etykiet parametrow procedury
              save_lab(str , tst , __id_param , zm);

              inc( tst , TypeToByte(txt[1]) );
             end;

           end;

   __pVar: begin

             idx:=t_prc[proc_nr].str;

             for _odd:=_doo-1 downto 0 do begin
              txt:=t_par[idx+_odd];


            // wczytamy nazwe parametru, usuwamy pierwszy znak okreslajacy typ
            // oraz znaki ktore nie naleza do nazwy etykiety

              str:='';
              add:='';
              i:=2;
              len:=length(txt);

              while i<=len do begin
               if _lab(txt[i]) then str:=str+txt[i] else Break;
               inc(i);
              end;

              while i<=len do begin
               add:=add+txt[i];
               inc(i);
              end;

              b:=lokal_name+ety+'.';

              tmp:=b+str;
              i:=l_lab(tmp);

            // szukamy najblizszej sciezki dla parametru

              while (i<0) and (pos('.',b)>0) do begin
               obetnij_kropke(b);

               tmp:=b+str;
               i:=l_lab(tmp);
              end;

              t_par[idx+_odd] := txt[1]+tmp+add;
             end;

           end;

    end;


 dreloc.use := old_bool;

 run_macro  := old_macro;

 save_lst(' ');

end;


function ByteToReg(var a: byte): char;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 case (a and $c0) of
  $40: Result := 'X';
  $80: Result := 'Y';
 else
  Result := 'A';
 end;

 a:=byte( a shl 2 );
end;


function RegToByte(const a: char): byte;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 case a of
  'A': Result := $00;
  'X': Result := $55;
  'Y': Result := $aa;
 else
  Result := $ff;
 end;

end;


procedure get_procedure(var ety,nam,zm: string; var i:integer);
(*----------------------------------------------------------------------------*)
(*  odczytujemy i zapamietujemy typy i nazwy parametrow w deklaracji .PROC    *)
(*  w zaleznosci od sposobu przekazywania parametrow zwiekszana jest liczba   *)
(*  przebiegow asemblacji PASS_END                                            *)
(*----------------------------------------------------------------------------*)
type _typBool = array [0..2] of Boolean;

var k, l, nr_param, j: integer;
    txt, str: string;
    ch, ptype: char;
    v: byte;
    old_bool: Boolean;

    treg: _typBool;
    all : _typStrREG;

begin
           reserved_word(ety,zm);               // sprawdz czy nazwa .PROC jest dozwolona

           old_bool  := run_macro;
           run_macro := false;

           save_lab(ety,proc_nr,__id_proc,zm);  // aktualny indeks do T_PRC = PROC_NR

           run_macro := old_bool;

           old_bool   := dreloc.use;            // koniecznie aby parametry procedury
           dreloc.use := false;                 // nie byly relokowalne

           t_prc[proc_nr].nam := nam;           // wlasciwa nazwa procedury
           t_prc[proc_nr].bnk := bank;          // zapisanie banku procedury
           t_prc[proc_nr].adr := adres;         // zapisanie adresu procedury

           t_prc[proc_nr].typ := __pDef;        // domyslny typ procedury 'D'

           t_prc[proc_nr].str := High(t_par);   // indeks do T_PAR, beda tam parametry procedury


           omin_spacje(i,zm);

           k:=0;  nr_param:=0;


           str:=zm[i];

           if not(test_char(i,zm,'(',#0)) then blad(zm,4); //blad_und(zm,str,8);

          // odczytujemy deklaracje parametrow ograniczonych nawiasami ( )
           if zm[i] = '(' then begin

            all:='';                 // tutaj zapiszemy kombinacje rejestrow CPU

            treg[0]:=false;
            treg[1]:=false;
            treg[2]:=false;

            proc:=true;
            proc_name:=ety+'.';

          // sprawdzamy poprawnosc nawiasow, usuwamy poczatkowy i koncowy nawias

            txt:=ciag_ograniczony(i,zm,true);

            omin_spacje(i,zm);

            ptype := __pDef;          // domyslny typ procedury __pDef

         // sprawdzamy czy jest okreslony typ procedury .REG
            if zm[i]='.' then begin
             //str:=get_datUp(i,zm,#0,false);
             str:=get_directive(i,zm);

             v := fCRC16(str);

             if not(v in [__reg, __var]) then blad_und(zm,str,68);

             ptype := str[2];
             t_prc[proc_nr].typ := ptype;
            end;

            if ptype=__pVar then
             if pass_end<3 then pass_end:=3;     // jesli sa parametry .VAR to musza byc conajmniej 3 przebiegi

          // sprawdzamy obecnosc deklaracji dla programowego stosu MADS'a

            if ptype=__pDef then begin
             adr_label(__STACK_POINTER, true);   // @stack_pointer, test obecnosci deklaracji etykiety
             adr_label(__STACK_ADDRESS, true);   // @stack_address, test obecnosci deklaracji etykiety
             adr_label(__PROC_VARS_ADR, true);   // @proc_vars_adr, test obecnosci deklaracji etykiety
            end;

            j:=1;
            ch:=' ';                  // jesli ch=' ' to odczytuj typ parametru

            while j<=length(txt) do begin

             if ch=' ' then begin
              v:=get_type(j,txt,zm,true);
              ch:=relType[ v ];       // typ parametru 'B', 'W', 'L', 'D' z relType
             end;


           // odczytujemy nazwe parametru lub !!! wyrazenie !!! (np. label+1)
           // parametry możemy rozdzielac znakiem przecinka
           // spacja sluzy do okreslenia nowego typu parametru

             omin_spacje(j,txt);
             str:=get_dat(j,txt,',',true);    // parametr lub wyrazenie
             if str='' then blad(zm,15);


           // jesli .REG to nazwy parametrow sa 1-literowe A,X,Y lub 2-literowe AX, AY itp.
           // nazwy parametrow moga powtorzyc sie tylko raz
           // dla .REG dopuszczalne sa tylko parametry typu .BYTE, .WORD, .LONG
             if ptype=__pReg then begin

               if not(TypeToByte(ch)=length(str)) then blad_und(zm,str,41);

               for l:=1 to length(str) do begin

                 v:=RegToByte(UpCase(str[l])) and 3;

                 if v=3 then
                  blad_und(zm,str[l],61)   // CPU doesn't have register ?
                 else
                  if treg[v] then
                   blad(zm,11)             // CPU doesn't have so many registers
                  else
                   treg[v]:=true;

               end;

             end;

             omin_spacje(j,txt);

           // wstepnie zapamietujemy etykiety parametrow jako wartosc NR_PARAM dla __pDef

             case ptype of
              __pDef: save_lab(str , nr_param , __id_param , zm);
              __pReg: all:=all+str;
//              __pVar: str:=proc_name+lokal_name+str;   // potem poszukamy "sciezki" do nazwy parametru
             end;

             str:=ch+str;  save_par(str);

             inc(k);              // zwiekszamy licznik odczytanych parametrow procedury

             inc( nr_param , TypeToByte(ch) );   // zwiekszamy NR_PARAM o dlugosc danych

             if txt[j]<>',' then
              ch:=' '
             else
              inc(j);

            end;    // while

           end;     // if zm[i] = '('


           if t_prc[proc_nr].typ = __pReg then begin
          // maksymalnie 3 bajty mozna przekazac za pomoca rejestrow
            if nr_param>3 then blad(zm,11);

          // zapisujemy kolejnosc rejestrow
            t_prc[proc_nr].reg := (RegToByte(all[1]) and $c0) or (RegToByte(all[2]) and $30) or (RegToByte(all[3]) and $0c);
           end;

           t_prc[proc_nr].par := k;
           t_prc[proc_nr].ile := nr_param;

           t_prc[proc_nr].use := not(exclude_proc);

           dreloc.use := old_bool;
end;


procedure test_wyjscia(var zm:string; const wyjscie:Boolean);
(*----------------------------------------------------------------------------*)
(*  testowanie zakonczenia asemblacji pliku                                   *)
(*----------------------------------------------------------------------------*)
begin

 if not(wyjscie) then
  if not(run_macro) and not(icl_used) then
   if ifelse<>0 then blad(zm,1) else
    if proc or macro then blad(zm,17) else  // !!! koniecznie !!! ... or macro
     if struct.use then blad(zm,56) else
      if enum.use then blad(zm,122) else
       if aray then blad(zm,60) else
        if rept then blad(zm,43) else
         if lokal_nr>0 then blad(zm,29) else
          if pag_idx>0 then blad(zm,65) else
           if whi_idx>0 then blad(zm,89) else
            if test_idx>0 then blad(zm,96) else
             if segment>0 then blad(zm,113);
end;


function fgetB(var i:integer): byte;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 Result := t_lnk[i];
 inc(i);
end;

function fgetW(var i:integer): integer;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 Result := t_lnk[i] + t_lnk[i+1] shl 8;
 inc(i,2);
end;

function fgetL(var i:integer): cardinal;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 Result := t_lnk[i] + t_lnk[i+1] shl 8 + t_lnk[i+2] shl 16;
 inc(i,3);
end;

function fgetD(var i:integer): cardinal;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 Result := t_lnk[i] + t_lnk[i+1] shl 8 + t_lnk[i+2] shl 16 + t_lnk[i+3] shl 24;
 inc(i,4);
end;

function fgetS(var i:integer): string;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var x, y: integer;
begin
 Result:='';

 x:=fgetW(i);

 for y:=x-1 downto 0 do Result:=Result+chr( fgetB(i) );
end;


procedure flush_link;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var j, k: integer;
begin
 k:=dlink.len;

 save_lst('a');

 if k>0 then
  for j:=0 to k-1 do save_dst(t_ins[j]);

 inc(adres,k);

 if dlink.emp>0 then begin
  save_hea;  org:=true;
  inc(adres,dlink.emp);
  dlink.emp:=0;
 end;

end;


procedure get_address(var i:integer; var zm:string);
(*----------------------------------------------------------------------------*)
(* nowy adres asemblacji dla .PROC lub .LOCAL                                 *)
(*----------------------------------------------------------------------------*)
var txt: string;
begin
      t_end[end_idx].old:=adres;

      // sprawdzamy czy jest nowy adres asemblacji dla .PROC lub .LOCAL

      omin_spacje(i,zm);

      if zm[i]=',' then begin
        __inc(i,zm);
        txt:=get_dat(i,zm,'(',true);

        blokuj_zapis:=true;  // wymuszamy zapis ORG-a jesli wystapil wczesniej
        save_dst(0);
        blokuj_zapis:=false;

        org_ofset := adres;

        adres := integer( oblicz_wartosc(txt,zm) );

        org_ofset := adres - org_ofset;

        omin_spacje(i,zm);
      end;
end;


procedure get_address_update;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 dec(adres, t_end[end_idx-1].adr);
 inc(adres, t_end[end_idx-1].old);

 dec(end_idx);
end;


procedure save_extLabel(k:integer; var ety,zm:string; v:byte);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var txt: string;
    len: byte;
    isProc: Boolean;
begin

  omin_spacje(k,zm);

  if v=__proc then begin                  // etykieta external deklaruje procedure

   proc_nr:=proc_idx;                     // koniecznie przez ADD_PROC_NR

   if pass=0 then begin
     txt:='##'+ety;                       // zapisujemy etykiete ze znakami ##
     get_procedure(txt,ety,zm,k);         // odczytujemy parametry

     proc:=false;                         // koniecznie wylaczamy PROC
     proc_name:='';                       // i koniecznie PROC_NAME:=''
   end;

   add_proc_nr;                           // zwiekszamy numer koniecznie

   save_lab(ety,extn_idx,__id_ext,zm);

   len:=2;                                // typu .WORD
   isProc:=true;

  end else begin

   dec(v, __byteValue);                   // normalna etykieta external

   save_lab(ety, extn_idx, __id_ext, zm);

   len:=v;
   isProc:=false;

  end;

  t_extn[extn_idx].nam:=ety;              // SAVE_EXTN
  t_extn[extn_idx].siz:=relType[len];     //
  t_extn[extn_idx].prc:=isProc;           //

  inc(extn_idx);

  if extn_idx>High(t_extn) then SetLength(t_extn,extn_idx+1);
end;


procedure get_maeData(var zm:string; var i:integer; const typ:char);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var _odd, _doo, idx, j, tmp: integer;
    txt, hlp: string;
    v, war: byte;
    yes: Boolean;

    par: _strArray;
begin

   omin_spacje(i, zm);

   if test_char(i,zm) then blad(zm,23);


   if proc then
    yes := t_prc[proc_nr-1].use
   else
    yes := true;

   data_out:=true;    // wymus pokazanie w pliku LST podczas wykonywania makra

   save_lst('a');

   SetLength(par, 1);
   get_parameters(i,zm,par,true);

   _doo:=High(par);

   if _doo > 0 then begin

    _odd:=0;
    war:=0;

    if (typ in ['B','S','C']) and (_doo>1) then begin

     txt:=par[0];     // mozliwa wartosc, ktora bedziemy dodawac do reszty ciagu
                      // pod warunkiem ze ciag liczy wiecej niz 1 element

     if txt = '' then blad(zm, 58);

     if txt[1] in ['+','-'] then begin
      j:=1; war:=byte( oblicz_wartosc_noSPC(txt,zm,j,#0,'B') );
      inc(_odd);
     end;

    end;


    for idx:=_odd to _doo-1 do begin               // wlasciwe dekodowanie ciagu
     txt:=par[idx];

     if txt<>'' then
     if txt[1] in AllowQuotes then begin           // if text string

      j:=1; hlp:=get_string(j,txt,zm,true);

      omin_spacje(j,txt);

      if length(txt)>=j then
       if not(txt[j] in ['*','+','-']) then blad(zm,8,txt[j]);

      v:=war;

      inc(v, test_string(j,txt,'F'));

      if typ='C' then inc(hlp[length(hlp)], $80);

      if yes then
       if typ='S' then
        save_dta(0,hlp,'D', v)
       else
        save_dta(0,hlp,'C', v);

     end else

      case typ of
       'B', 'H', 'S', 'C':
            begin
             if typ='H' then txt:='$'+txt;

             j:=1;  v := byte( oblicz_wartosc_noSPC(txt,zm,j,#0,'B') );

             if typ='S' then v:=ata2int(v);

             inc(v, war);

             if yes then begin
	      save_dst(v);

              inc(adres);
	     end;

            end;

       'W', 'D':
            begin
             j:=1;  tmp := integer( oblicz_wartosc_noSPC(txt,zm,j,#0,'A') );

             if yes then
              if typ = 'W' then
               save_dstW( tmp )
              else begin
               save_dst( byte(tmp shr 8) );   // hi
               save_dst( byte(tmp) );         // lo
              end;

             if yes then inc(adres,2);
            end;

      end;

    end;

   end else
    blad(zm,58);		// np. '.by .len(temp)'

end;


function asm_test(var lar,rar,old, jump:string; const typ,op:byte): int5;
(*----------------------------------------------------------------------------*)
(* generujemy kod testujacy warunek dla .WHILE, .TEST                         *)
(*----------------------------------------------------------------------------*)
var hlp: int5;
    txt: string;
    adr: integer;
begin

 adr:=adres;

 if lar[1]='#' then blad(old,58);   // argument nierealny :)

 case typ of
  1: txt:='CPB';
  2: txt:='CPW';
  3: txt:='CPL';
 else
  txt:='CPD';
 end;

 TestWhileOpt:=not(op in [0,4]);    // krótszy kod jesli operator '=', '<>'

 txt:=txt+#32+lar+#32+rar;
 Result:=asm_mnemo(txt, old);

(*----------------------------------------------------------------------------*)
(*  0 <>      4 =           xor 4                                             *)
(*  1 >=      5 <                                                             *)
(*  2 <=      6 >                                                             *)
(*----------------------------------------------------------------------------*)

 case op of
   0: txt:='JNE';                   // <>
   1: txt:='JCS';                   // >=
   2: txt:='JCC '+jump;             // <=
   4: txt:='JEQ';                   // =
   5: txt:='JCC';                   // <
   6: txt:='SEQ';                   // >
 end;


 if op in [2,6] then begin

   hlp:=asm_mnemo(txt,old);
   addResult(hlp,Result);

   if op=2 then
    txt:='JEQ'
   else begin
    test_skipa;
    txt:='JCS';
   end;

 end;


 txt:=txt+#32+jump;
 hlp:=asm_mnemo(txt,old);
 addResult(hlp,Result);

 adres := adr;                      // przywracamy poczatkowa wartosc ADRES
end;


procedure create_long_test(const _v, _r:byte; var long_test, _lft, _rgt:string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var txt: string;
begin

   txt:='';

   case _v xor 4 of
    0: txt:='<>';
    1: txt:='>=';
    2: txt:='<=';
    4: txt:='=';
    5: txt:='<';
    6: txt:='>';
   end;

   if long_test<>'' then long_test:=long_test+'\';

   long_test:=long_test+'.TEST '+mads_param[_r]+_lft + txt + _rgt+'\ LDA:SNE#1\.ENDT\ LDA#0';

   long_test:=long_test+'\.IF .GET[?I-1]=41\ AND EX+?J-2+1\ STA EX+?J-2+1\ ?I--\ ELS\ STA EX+?J+1\ ?J+=2\ EIF\';

end;


procedure wyrazenie_warunkowe(var i:integer; var long_test, zm,left,right:string; var v,r:byte; const strend: string);
(*----------------------------------------------------------------------------*)
(* generowanie kodu dla warunku .WHILE, .TEST                                 *)
(*----------------------------------------------------------------------------*)
var str, txt, _lft, _rgt, kod: string;
    k, j: integer;
    _v, _r: byte;
begin

   if zm='' then blad(zm,23);

   r:=get_type(i,zm,zm,false);

   omin_spacje(i,zm);

   str:=get_dat(i,zm,#0, false);

   k:=1;

   right:='';
   left:='';        // czytamy do LEFT dopóki nie napotkamy operatorów '=', '<', '>', '!'

   if str<>'' then
    while not(_ope(str[k])) and not(test_char(k,str)) do begin

       if str[k] in AllowBrackets then
         left:=left + ciag_ograniczony(k,str,false)
       else begin
        if str[k]<>' ' then left:=left + str[k];
        inc(k);
       end;

   end;


   if (r=0) and (var_idx>0) then             // brak typu, jesli etykieta byla przez .VAR to odczytamy typ
    for j := High(t_var)-1 downto 0 do
     if (t_var[j].typ='V') and (t_var[j].nam=left) then begin r:=t_var[j].siz; Break end;

   if r=0 then r:=2;                         // domyslnym typem jest .WORD


   omin_spacje(k,str);


   v:=$ff;

   if left<>'' then begin

(*----------------------------------------------------------------------------*)
(*  0 <>      4 =           xor 4                                             *)
(*  1 >=      5 <                                                             *)
(*  2 <=      6 >                                                             *)
(*----------------------------------------------------------------------------*)

   case str[k] of            // szukamy znanej kombinacji operatorów

      #0: v:=$80;             // koniec ciągu

     '=': case str[k+1] of
           '=': begin
                 v:=4;       // ==
                 inc(k);
                end;
          else
           v:=4;             // =
          end;

     '!': case str[k+1] of
           '=': v:=0;        // !=
          end;

     '<': case str[k+1] of
           '>': v:=0;        // <>
           '=': v:=2;        // <=
          else
           v:=5;             // <
          end;

     '>': case str[k+1] of
           '=': v:=1;        // >=
          else
           v:=6;             // >
          end;

   end;



     if v<$80 then begin

       if v<4 then
        inc(k,2)
       else
        inc(k);

       if _ope(str[k]) then blad(zm,8, str[k]);

       v:=v xor 4;

       omin_spacje(k,str);

       right:=get_dat(k,str,#0,true);      //get_dat_noSPC(k,str,zm,#0);

     end else
        if v=$80 then begin      // dla pustego ciagu domyslna operacja '<>0'
           v:=4;
           right:='#0';
        end;

   end;


 // V = $FF oznacza brak operatora

   if (left='') or (right='') or (v=$ff) then begin
      blad(zm,58); koniec(2);
   end;


 // jesli występują operatory .OR, .AND to generujemy specjalny kod

  omin_spacje(k,str);

  kod:='';

  if not(test_char(k,str)) then begin

   txt:=get_dat(k,str,#0,true);

   if txt='.OR' then
    kod:='9'
   else
    if txt='.AND' then
     kod:='41';
{    else
     blad(zm,58);}

  end;


  if kod<>'' then begin

   if long_test='' then long_test:=long_test+'.LOCAL\.PUT[0]=0\?I=1\?J=0';

   omin_spacje(k,str);
   txt:=get_dat(k,str,#0,false);

   _r:=0;
   _v:=0;
   _rgt:='';
   _lft:='';

   j:=1; wyrazenie_warunkowe(j, long_test, txt,_lft,_rgt, _v, _r, '.PUT[?I]='+kod+'\ ?I++');
  end;


  if (long_test<>'') then begin
   create_long_test(v, r, long_test, left, right);
   long_test:=long_test+strend;
  end;

end;


function BCD(const l: integer): byte;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 Result := (l div 10) * 16 + (l mod 10);
end;


procedure save_fl(var a,old:string);
(*----------------------------------------------------------------------------*)
(*  zapisujemy liczbe real w formacie FP Atari                                *)
(*  wykorzystujemy wlasciwosci kodowania liczby real przez Delphi             *)
(*----------------------------------------------------------------------------*)
var i, e: integer;
    x: double;
    n: int64;
const
    powers : array[0..98] of double = (
    1e-98, 1e-96, 1e-94, 1e-92, 1e-90, 1e-88, 1e-86, 1e-84, 1e-82, 1e-80,
    1e-78, 1e-76, 1e-74, 1e-72, 1e-70, 1e-68, 1e-66, 1e-64, 1e-62, 1e-60,
    1e-58, 1e-56, 1e-54, 1e-52, 1e-50, 1e-48, 1e-46, 1e-44, 1e-42, 1e-40,
    1e-38, 1e-36, 1e-34, 1e-32, 1e-30, 1e-28, 1e-26, 1e-24, 1e-22, 1e-20,
    1e-18, 1e-16, 1e-14, 1e-12, 1e-10, 1e-08, 1e-06, 1e-04, 1e-02, 1e+00,
    1e+02, 1e+04, 1e+06, 1e+08, 1e+10, 1e+12, 1e+14, 1e+16, 1e+18, 1e+20,
    1e+22, 1e+24, 1e+26, 1e+28, 1e+30, 1e+32, 1e+34, 1e+36, 1e+38, 1e+40,
    1e+42, 1e+44, 1e+46, 1e+48, 1e+50, 1e+52, 1e+54, 1e+56, 1e+58, 1e+60,
    1e+62, 1e+64, 1e+66, 1e+68, 1e+70, 1e+72, 1e+74, 1e+76, 1e+78, 1e+80,
    1e+82, 1e+84, 1e+86, 1e+88, 1e+90, 1e+92, 1e+94, 1e+96, 1e+98 );
begin

 val(a, x, i);
 if i>0 then blad(old,8,a[i]);

 // Make X positive
 e := $0E;
 if x < 0 then begin
  e := $8E;
  x := -x;
 end;

 // If number is too small, store 0
 if x < 1e-99 then begin
  save_dst(0);
  save_dst(0);
  save_dst(0);
  save_dst(0);
  save_dst(0);
  save_dst(0);

  inc(adres,6);
  exit;
 end;

 if x >= 1e+98 then blad(old,0);   // przekroczony zakres FP Atari

 // Search correct exponent
 for i := 0 to 98 do begin
  if x < powers[i] then begin
   n := Round(x * 10000000000.0 / powers[i]);
   save_dst(e + i);
   save_dst(BCD( n div 100000000 ));
   save_dst(BCD( (n div 1000000) mod 100 ));
   save_dst(BCD( (n div 10000) mod 100 ));
   save_dst(BCD( (n div 100) mod 100 ));
   save_dst(BCD( n mod 100 ));

   inc(adres,6);             // zapisalismy 6 bajtow
   exit;
  end
 end

end;


function getMemType(var i: integer; var zm: string): byte;
(*----------------------------------------------------------------------------*)
(* typ pamieci dla blokow Sparta DOS X : M-ain, E-xtended, 0..$7f             *)
(*----------------------------------------------------------------------------*)
begin

 omin_spacje(i,zm);

 Result := 0;

 if _alpha(zm[i]) then begin

   case UpCase(zm[i]) of
    'M': Result:=0;         // M[ain]
    'E': Result:=2;         // E[xtended]
   else
    blad(zm,23);
   end;

 end else begin
  Result:=byte( oblicz_wartosc_noSPC(zm,zm,i,#0,'B') );

  if Result>127 then blad(zm,0);
 end;

 memType := Result;
end;


function get_command(var i: integer; var zm: string): integer;
(*----------------------------------------------------------------------------*)
(* odczyt dyrektywy lub pseudorokazu w bloku .MACRO, .REPT                    *)
(*----------------------------------------------------------------------------*)
var ety: string;
begin

 Result:=0;

 if zm<>'' then begin

    omin_spacje(i, zm);

    ety:='';

    if labFirstCol and (i=1) then
     if zm[i]='.' then
      ety:=get_directive(i,zm)
     else begin
      ety:=get_datUp(i,zm,#0,false);

      if length(ety)<>3 then ety:='' else
       if not(reserved(ety)) then ety:='';

     end;


    if ety='' then begin
     ety:=get_datUp(i,zm,#0,false);

     omin_spacje(i,zm);

     if ety<>'' then
      if ety[1]<>'.' then
       if not(test_char(i,zm)) then
        if zm[i]='.' then
         ety:=get_directive(i,zm)
        else
         ety:=get_datUp(i,zm,#0,false);

    end;

    if ety<>'' then
     if ety[1]='.' then
      Result:=fCRC16(ety)
     else
      Result:=fASC(ety);

 end;

end;


function dirMACRO(var zm:string): byte;
(*----------------------------------------------------------------------------*)
(*  odczyt makra zdefiniowanego przez dyrektywy .MACRO, .ENDM [.MEND]         *)
(*  !!! wyjatkowo dyrektywa .END nie może kończyc definicji makra !!!         *)
(*----------------------------------------------------------------------------*)
var k: integer;
begin
   save_lst(' ');                               // .MACRO

   k:=1;

   Result := get_command(k,zm);

   if (Result=__macro) and macro then blad(zm,17);

   if Result = __endm then macro := false;

   if (pass=0) and if_test then save_mac(zm);   // !!! makra zapisujemy tylko w 1 przebiegu !!!

   zapisz_lst(zm);
end;


procedure reptLine(var txt: string);
(*----------------------------------------------------------------------------*)
(*  podstawianie parametrow w bloku .REPT                                     *)
(*----------------------------------------------------------------------------*)
var ety, tmp: string;
    j, k, war: integer;
begin
           j:=1;
           while j<=length(txt) do
            if test_param(j,txt) then begin

             k:=j;
             if txt[j]=':' then inc(j) else inc(j,2);       // [:par] || [%%par]

             ety:=read_DEC(j, txt);

             war:=StrToInt(ety);

             if war<High(reptPar) then begin

              delete(txt,k,j-k);  dec(j,j-k);

              tmp:=reptPar[war];

              war:=oblicz_wartosc(tmp, txt);

              tmp:=IntToStr(war);

              insert(tmp,txt,k);
              inc(j,length(tmp));
             end;

            end else inc(j);

end;


function dirENDR(var zm,a,old_str:string; cnt: integer): integer;
(*----------------------------------------------------------------------------*)
(*  .ENDR  -  wykonanie petli .REPT                                           *)
(*----------------------------------------------------------------------------*)
var lntmp, i, j, k, max, rile, rpt: integer;
    tmp, ety: string;
    old_if_test: Boolean;
    tmpPar: _strArray;
begin

 Result:=0;
 max:=0;

      if if_test then begin

         wymus_zapis_lst(zm);

         rept        := false;
         rept_run    := true;

         rile        := ___rept_ile;

         lntmp       := line_add;

         tmpPar      := reptPar;

         line_add    := t_rep[cnt].lin;

         old_if_test := if_test;


{
	 writeln(pass,',','-------------------');
         for i := t_rep[cnt].fln to t_rep[cnt].lln do writeln(t_mac[i]);
         for i := 0 to High(t_rep)-1 do  writeln(t_rep[i].fln,',',t_rep[i].lln,',',t_rep[i].lin,' - ',t_rep[i].lln-t_rep[i].fln);

         halt;
}


         if not(run_macro) then begin
          tmp := 'REPT';
          put_lst(show_full_name(tmp,false,true));
         end;


         tmp := t_mac[t_rep[cnt].fln];                    // pierwsza linia z .REPT

         i:=1;
         omin_spacje(i, tmp);
         ety:=get_directive(i, tmp);

         if fCRC16(ety)<>__rept then
          blad(zm,51)
         else begin

          reptLine(tmp);

          get_parameters(i,tmp, reptPar, false, #0,#0);

          if High(reptPar)=0 then blad(zm,23);            // Unexpected end of line

          max := oblicz_wartosc(reptPar[0],zm);           // liczba powtorzen petli
          if max<0 then blad(zm, 0);                      // !!! mozliwa wartosc powyzej $ffff !!!

          reptPar[0]:=IntToStr(Int64(High(reptPar))-1);   // liczba parametrów przekazana do .REPT
         end;


         ___rept_ile := 0;          // !!! koniecznie w tym miejscu po odczycie linii .REPT


         for  j:=0 to max-1 do begin

	  rpt:=0;

          i := t_rep[cnt].fln+1;                          // first line

          while i <= t_rep[cnt].lln do begin

            tmp := t_mac[i];

            k:=1;
            omin_spacje(k, tmp);
            ety:=get_directive(k, tmp);

            if fCRC16(ety) = __rept then begin

	     inc(rpt);

             inc(i, dirENDR(zm,a,old_str, cnt + rpt));

            end else
             analizuj_mem(i,i+1, zm,a,old_str, j,j+1, true);

            inc(i);
          end;

         end;


         rept_run  := false;

         if not(run_macro) and not(rept) then put_lst(show_full_name(a,full_name,true));


         line_add    := lntmp;

         if_test     := old_if_test;

         ___rept_ile := rile;

         reptPar     := tmpPar;

         Result := t_rep[cnt].lln - t_rep[cnt].fln;

       end;
end;


procedure get_rept(var i: integer; var zm: string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var k, j: integer;
    par: _strArray;
begin

 j:=i;

 get_parameters(i,zm, par, false, #0,#0);

 if High(par)=0 then blad(zm,23);            // Unexpected end of line


 k:=High(t_rep);

 t_rep[k].fln := High(t_mac);

 t_rep[k].lin := line;


 t_rep[rept_cnt].idx := k;

 inc(rept_cnt);

 SetLength(t_rep, k+2);


 save_mac('.REPT ' + copy(zm,j,length(zm)));

// save_end(__endr);

end;


procedure get_endr;
begin

  dec(rept_cnt);

  t_rep[t_rep[rept_cnt].idx].lln := High(t_mac) - 1;

//  dec_end(zm, __endr);

end;


function dirREPT(var str: string): byte;
(*----------------------------------------------------------------------------*)
(*  analiza linii gdy wystapilo .REPT                                         *)
(*----------------------------------------------------------------------------*)
var i, k: integer;
    zm: string;
begin

 Result:=0;

 save_lst(' ');

 i:=1;

 while i<=length(str) do begin

   zm:=get_dat(i,str,'\',false);

   k:=1;
   Result := get_command(k,zm);

   case Result of
            __rept: get_rept(k,zm);
    __endr, __dend: get_endr;
   end;

  //  if not(komentarz) then

    if if_test and not(Result in [__rept, __endr, __dend]) then begin
      save_mac(zm);
      zapisz_lst(zm);
    end;

   if str[i]='\' then
    inc(i)
   else
    Break;

 end;

end;


function get_vars_type(var i:integer; var zm:string; var typ:char; var i_str: integer; var n_str: string): integer;
(*----------------------------------------------------------------------------*)
(* odczytujemy typ dla zmiennych .BYTE, .WORD, .LONG, .DWORD, .STRUCT|.ENUM   *)
(*----------------------------------------------------------------------------*)
var txt: string;
    k, x: integer;
begin

     omin_spacje(i,zm);

     Result:=0;
     k:=i;

     if zm[i]='.' then begin

       txt:=get_directive(i,zm);
       Result:=fCRC16(txt);

       if Result in [__byte..__dword] then
         dec(Result, __byteValue)
       else begin
         Result:=0;     // to nie jest dyrektywa okreslajaca typ danych !!! V=0 !!!
         i:=k;          // przywracamy poprzednie wartosci
       end;

     end else begin

       txt:=get_lab(i,zm, true);    // zatrzyma sie jesli brak etykiety

       x:=load_lab(txt, true);

       if x<0 then
        i:=k                        // etykieta nie zostala zdefiniowana
       else
        case t_lab[x].bnk of

           __id_enum:
           begin
            Result:=t_lab[x].adr;

            n_str := txt;

//            typ:='E';
           end;

         __id_struct:
           begin
            Result:=t_str[t_lab[x].adr].siz;

            i_str := t_lab[x].adr;
            n_str := txt;

            typ:='S';
           end;

        else
         i:=k;
        end;

     end;

end;


procedure get_vars(var i:integer; var zm:string; var par:_strArray; const mne: byte);
(*----------------------------------------------------------------------------*)
(*  .VAR .TYPE v0 [=expression], v1 [=expression] .TYPE v3 [=expression] v4   *)
(*  .VAR v0 [=expression] .TYPE v1 [=expression] v2 .TYPE [=address]          *)
(*                                                                            *)
(*  odczyt parametrow dla dyrektywy .VAR                                      *)
(*----------------------------------------------------------------------------*)
var idx, _doo, _odd, k, v, i_str: integer;
    txt, str, n_str: string;
    tst: Int64;
    typ: char;
begin

     i_str:=0;
     n_str:='';

     typ:='V';

     v:=get_vars_type(i,zm, typ, i_str, n_str);

     get_parameters(i,zm,par,false);

     idx:=1;

     if zm[i]=':' then begin                // liczba powtorzen
      inc(i);
      txt:=get_dat(i,zm,',',true);
      idx:=integer( oblicz_wartosc(txt,zm) );
      testRange(zm, idx, 0);
     end;

     _doo:=High(par);

     if _doo=0 then blad(zm,23);            // brak zmiennych - Unexpected end of line

     omin_spacje(i,zm);

     if v=0 then
      if zm[i]='.' then

       v:=get_type(i,zm,zm,true)            // typ zmiennej

      else begin

       if test_char(i,zm) then
        txt:=par[_doo-1]
       else begin
        txt:=get_dat(i,zm,',',true);
        inc(_doo);
       end;

       k:=1;
       v:=get_vars_type(k,txt,typ, i_str, n_str);

       if v=0 then
        blad_und(zm,txt,50)                 // nie zostal okreslony typ zmiennej "Missing type label"
       else begin
        par[_doo-1]:=copy(txt,k,length(txt));

        dec(_doo);                          // udalo sie, ostatni element pomijamy
       end;

      end;


     for _odd:=0 to _doo-1 do begin
      txt:=par[_odd];

      k:=1;  str:=get_lab(k, txt, true);    // sprawdzamy czy etykieta posiada poprawne znaki

      //if str='' then blad_ill(zm,txt[1]);   // pierwszy znak etykiety jest niewlasciwy


      tst:=0;

      if txt[k]='=' then begin              // czy zmienna jest inicjowana ('=')

        if (mne=__zpvar) and (pass=pass_end) then warning(114);

        txt:=copy(txt,k+1,length(txt));

        tst:=oblicz_wartosc(txt,zm);

        if ValueToType(tst) > v then blad(zm,0);

      end else
       if not(test_char(k,txt)) then blad(zm,8,txt[k]);  // wystapil niedozwolony znak


        if proc then                           // SAVE_VAR
         t_var[var_idx].lok := proc_lokal      //
        else                                   //
         t_var[var_idx].lok := end_idx;        //
                                               //
        if proc and (lokal_name<>'') then      //
         t_var[var_idx].nam := lokal_name+str  //
        else                                   //
         t_var[var_idx].nam := str;            //
                                               //
        t_var[var_idx].siz := v;               //
        t_var[var_idx].cnt := idx;             //
        t_var[var_idx].war := cardinal (tst);  //
                                               //
        t_var[var_idx].adr := -1;              //
                                               //
        t_var[var_idx].id  := var_id;          //
        t_var[var_idx].typ := typ;             //
        t_var[var_idx].idx := i_str;           //
        t_var[var_idx].str := n_str;           //

        if proc then                                //
         t_var[var_idx].exc := t_prc[proc_nr-1].use //
        else                                        //
         t_var[var_idx].exc := true;                //

        inc(var_idx);

        if var_idx>High(t_var) then SetLength(t_var, var_idx+1);

     end;

end;


procedure opt_h_minus;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin
 opt:=opt and byte(not(opt_H));
end;


procedure upd_structure(var ety, zm: string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var idx: integer;
    txt: string;
begin
           struct.cnt := 0;

           txt:=lokal_name+ety;      // pelna nazwa struktury .STRUCT

          // sprawdzamy czy mamy juz zapamietana ta strukture
           idx:=loa_str(txt, struct.id);

          // nie znalazl ofsetu do tablicy (idx = -1)
           if idx<0 then begin

            save_str(txt,adres,0,1,adres,bank);      // dopisz do tablicy T_STR nowa strukture

            struct.idx:=loa_str(txt, struct.id);

            save_lab(ety,struct.idx, __id_struct,zm);

           end else begin
          // znalazl ofset do tablicy
            struct.idx:=idx;

            save_lab(ety,struct.idx, __id_struct,zm);
           end;

           if pass_end<3 then pass_end:=3;     // jesli sa struktury to musza byc conajmniej 3 przebiegi

end;



procedure search_comment_block(var i:integer; var zm,txt:string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var k: integer;
begin

 if (zm<>'') and (i<length(zm)) then begin

    k:=i;

    if (zm[i]='/') and (zm[i+1]='*') then begin
     komentarz:=true; inc(i,2);
    end;

    while komentarz and (i<=length(zm)) do
      if (zm[i]='*') and (zm[i+1]='/') then begin
       inc(i,2);
       txt:=txt+copy(zm,k,i-k);

       komentarz:=false; Break
      end else
       inc(i);

 end;

end;



procedure wypisz(var i: integer; var zm: string);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var txt: string;
    old_empty, old_firstorg: Boolean;
    old_adres: integer;
begin
       //    save_lst(' ');

       omin_spacje(i,zm);

       if not(test_char(i,zm)) then begin

           pisz   := true;
           branch := true;             // dla .PRINT nie istnieje relokowalnosc

           old_firstorg := first_org;
           first_org    := false;

           old_adres := adres;
           if adres<0 then adres := $0100;

           old_empty := empty;
           empty     := false;

           txt       := end_string;

           end_string := '';

           oblicz_dane(i,zm,zm,4);

           pisz  := false;

           empty := old_empty;

           adres := old_adres;

           first_org := old_firstorg;

           save_lst(' ');
           justuj;
           put_lst(t+zm);

           save_lst(' ');

           zm:=end_string;             // !!! aby umiescil tekst w listingu !!!

           end_string := txt + end_string + #13#10;

       end;
end;


procedure analizuj_linie (var zm,a,old_str:string; var nr:integer; var end_file,wyjscie:Boolean);
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
const
    tora: array [0..7] of byte = ($80,$40,$20,$10,8,4,2,1);

var g: file;
    f: textfile;
    v, r, opt_tmp: byte;
    ch, rodzaj, typ: char;
    i, k, j, m, _odd, _doo, idx, idx_get, rpt, old_ifelse, old_rept, indeks: integer;
    old_rept_cnt: integer;
    old_loopused, old_icl_used, old_case, old_run_macro, old_komentarz, yes: Boolean;
    ety, txt, str, tmp, old_macro_nr, long_test, tmpZM: string;
    war: Int64;
    tst, vtmp: cardinal;

    reloc_value: relVal;

    mne      : int5;
    par, tlin: _strArray;
    old_trep : _reptArray;

    label JUMP, LOOP, LOOP2, JUMP_2;
begin


if (adres > $FFFF) and (pass = pass_end) then warning(128);


LOOP2:

  i:=1;

  if not(struct.use) and not(enum.use) then label_type:='V';

  overflow:=false;

  mne.l:=0; rpt:=0;

  data_out:=false;

  reloc_value.use:=false; reloc_value.cnt:=0; rel_used:=false;

  m:=i;                     // zapamietujemy poczatkowa wartosc 'i'


  if zm='' then begin

   mne_used := false;       // nie zostal odczytany mnemonik (!!! koniecznie w tym miejscu !!!)

   save_lst(' ');
   put_lst(t);

   exit;
  end;


LOOP:

(*----------------------------------------------------------------------------*)
(*  odczytujemy etykiete z lewej strony, od pierwszego znaku w linii          *)
(*  jesli jest zakonczona dwukropkiem to pomijamy dwukropek                   *)
(*----------------------------------------------------------------------------*)
  ety:=get_lab(i,zm, false);
  if (zm[i]=':') and test_char(i+1,zm,' ',#0) then inc(i);

  omin_spacje(i,zm);


(*----------------------------------------------------------------------------*)
(*  a moze jest jakas etykieta poprzedzona bialymi spacjami i zakonczona  ':' *)
(*----------------------------------------------------------------------------*)
  if ety='' then begin
   k:=i;
   txt:=get_lab(i,zm, false);

   if txt<>'' then
    if ((zm[i]=':') and test_char(i+1,zm,' ',#0)) or struct.use or enum.use then begin
     ety:=txt;
     __inc(i,zm);
    end else
     i:=k;

  end;


(*----------------------------------------------------------------------------*)
(* odczyt wiekszej liczby pól struktury .STRUCT                               *)
(* jesli wiersz zaczyna sie od np.: .BYTE odczyt realizuje __dta ...          *)
(*----------------------------------------------------------------------------*)
  if struct.use and (ety<>'') then begin
   i:=1;
   get_parameters(i,zm,par,false);
  end;


(*----------------------------------------------------------------------------*)
(* etykiety moga byc rozkazami CPU lub pseudo rozkazami jesli labFirstCol=true*)
(* etykiet w stylu MAE to nie dotyczy, one sa rozpoznawane klasycznie         *)
(* nie dotyczy to takze etykiet deklarowanych w .STRUCT                       *)
(*----------------------------------------------------------------------------*)
  if (length(ety)=3) and not(struct.use) and not(mae_labels) and labFirstCol then
   if reserved(ety) then begin
     i:=m;
     ety:='';
   end;


(*----------------------------------------------------------------------------*)
(*  pierwszymi znakami moga byc tylko znaki poczatkujace nazwe etykiety,      *)
(*  znaki konca linii oraz '.', ':', '*', '+', '-', '='                       *)
(*  dopuszczalne sa instrukcje generujace kod 6502  #IF #WHILE #END           *)
(*----------------------------------------------------------------------------*)
//  if not(aray) and not(struct.use) and not(enum.use) then
   if not(_first_char(zm[i])) and not(test_char(i,zm)) then

    case zm[i] of

     '#': begin
           tmp:=get_directive(i,zm);

           mne.l:=fCRC16(tmp);
           if not(mne.l in [__test, __while, __dend, __telse, __cycle]) then blad(zm,12);

           goto JUMP_2;

          end;

     '{': if end_idx>0 then begin

           if t_end[end_idx-1].sem then blad(zm,58);

           t_end[end_idx-1].sem:=true;
           inc(i);

           goto LOOP;

          end else
           blad(zm,12);

     '}': if end_idx>0 then
           if t_end[end_idx-1].sem then begin
            __inc(i,zm);

            if not(test_char(i,zm)) then blad(zm,58);

            mne.l:=t_end[end_idx-1].kod;
           end else
            blad(zm,12);

    else
     if (mne.l=0) and not(aray) and not(struct.use) and not(enum.use) then blad(zm,12);
    end;

(*----------------------------------------------------------------------------*)
(*  sprawdzamy czy wystapila deklaracja lokalna etykiety                      *)
(*  znak '=' moze zastepowac EQU, nie musi byc poprzedzony "bialymi spacjami" *)
(*  znaki '+=' , '-=' zastepuja dodawanie i odejmowanie wartosci od etykiety  *)
(*  znaki '--' , '++' zastepuja zmniejszanie i zwiekszanie wartosci etykiety  *)
(*----------------------------------------------------------------------------*)
  tmpZM:=zm;

  if zm[i] in ['+','-'] then
   if (ety<>'') and (zm[i+1] in ['+','-','=']) then
    operator_zlozony(i,zm,ety, false)
   else
    blad(zm,4);

  if (zm[i]='=') and not(aray) and not(struct.use) and not(enum.use) then begin
   mne.l:=__addEqu; __inc(i,zm);                // wymuszamy wykonanie __addEQU

   save_lst(' ');

   goto JUMP;
  end;

  if ifelse>0 then save_lst(' ');


(*----------------------------------------------------------------------------*)
(*  znak okreslajacy liczbe powtorzen linii ':'                               *)
(*----------------------------------------------------------------------------*)
   if macro_rept_if_test and (zm[i]=':') then begin
    save_lst('a');

    inc(i);
    loop_used:=true;

    txt:=get_dat(i,zm,',',true);
    _doo:=integer( oblicz_wartosc(txt,zm) );
    testRange(zm, _doo, 0);

    old_rept    := ___rept_ile;
    ___rept_ile := 0;


  // test obecnosci czegokolwiek
    k:=i;  txt:=get_datUp(i,zm,#0,true);  i:=k;

    if (txt = '') or (txt[1] = '*') then blad(zm, 23);



    if struct.use then begin

     rpt:=_doo;
     omin_spacje(i,zm);

    end else begin

      old_case  := FOX_ripit;
      FOX_ripit := true;        // zwracamy wartosc licznika petli dla '#'

      indeks    := line_add;


      save_lab(ety,adres,bank,zm);

      idx:=High(t_mac);

      txt:=get_dat(i,zm,'\',false);
      save_mac(txt);

      line_add:=line-1;
      _odd := idx+1;

      par      := reptPar;

      SetLength(reptPar, 3);

      reptPar[0]:='1';
      reptPar[1]:='#';

      analizuj_mem(idx,_odd, zm,a,old_str, 0,_doo, true);


      reptPar   := par;

      loop_used := false;

      FOX_ripit := old_case;

      line_add  := indeks;

      SetLength(t_mac,idx+1);

      mne.l:=__nill;
      ety:='';
    end;

    ___rept_ile := old_rept;

   // FOX_ripit := false;
   end;


(*----------------------------------------------------------------------------*)
(*  sprawdzamy czy to dyrektywa, tylko niektore dyrektywy moga byc petlone:   *)
(*  .PRINT, .BYTE, .WORD, .LONG, .DWORD, .GET, .PUT, .HE, .BY, .WO, .SB, .FL, *)
(*  .CB, .CBM, .DEF  innych dyrektyw nie mozemy powtarzac                     *)
(*----------------------------------------------------------------------------*)
   if zm[i]='.' then begin

    tmp:=get_directive(i,zm);

    mne.l:=fCRC16(tmp);

    if not(mne.l in [__macro..__over]) then
     blad_und(zm,tmp,68)
    else
     if loop_used then
      if not(mne.l in [__byte..__dword, __def, __print, __sav, __get, __xget, __put, __he, __by, __wo, __sb, __fl, __bi, __cb, __cbm, __dbyte]) then blad(zm,36);

   end;


(*----------------------------------------------------------------------------*)
(*  zamiana IFT ELS EIF ELI na ich odpowiedniki .IF .ELSE .ENDIF .ELSEIF      *)
(*  zostala zrealizowane przez modyfikacje tablicy HASH                       *)
(*  !!! koniecznie tylko w tym miejscu, w innym kod nie zostanie wykonany !!! *)
(*----------------------------------------------------------------------------*)
  if (i<=length(zm)) and (UpCase(zm[i]) in ['E','I']) then begin

    j:=i;
    txt:=get_datUp(i,zm,#0,false);
    v:=fASC(txt);

    if length(txt)<>3 then
     i:=j
    else
     if not(v in [__if,__else,__endif,__elseif]) then
      i:=j
     else
      mne.l:=v;

  end;


(*----------------------------------------------------------------------------*)
(*  zamiana dyrektywy .OR na pseudo rozkaz ORG                                *)
(*  obsluga dyrektywy .NOWARN                                                 *)
(*----------------------------------------------------------------------------*)
  case mne.l of

       __or: mne.l:=__org;

   __nowarn: begin
              noWarning:=true;
              mne.l:=0;

//              omin_spacje(i,zm);       // !!! tutaj omijanie spacji niedopuszczalne !!!
              goto LOOP
             end;

  end;


  if not(skip_hlt) then test_skipa;


(*----------------------------------------------------------------------------*)
(*  odczytaj mnemonik                                                         *)
(*----------------------------------------------------------------------------*)

  if ety = '@' then begin
   save_lab(ety,adres,bank,zm);
   ety:='';
  end;


  k:=i;

  if (mne.l=0) and if_test and not(enum.use) then
   if i<=length(zm) then mne:=oblicz_mnemonik(i,zm,zm);


  if (mne.l = __define_run) then begin        // makro .DEFINE na poczatku wiersza

    if (t_mac[mne.i][1] = '~') then           // to makro jest wylaczone
     blad_und(zm, copy(t_mac[mne.i], 2, 255), 5);

    txt := t_mac[mne.i+2];

    if t_mac[mne.i+1] <> '' then              // wystepuja parametry makra
     get_define_param(i, zm, txt, StrToInt(t_mac[mne.i+1]));

    delete(zm, k, i-k);

    insert(txt, zm, k);

    goto LOOP2;

  end;


(*----------------------------------------------------------------------------*)
(*  odczyt etykiet wystepujacych w bloku .ENUM                                *)
(*----------------------------------------------------------------------------*)
  if enum.use then
   if (ety<>'') and (mne.l=0) then begin

    i:=1;

    get_parameters(i,zm,par,false);

    old_case   := dreloc.use;   // deklaracje etykiet w bloku .RELOC nie moga byc relokowalne
    dreloc.use := false;

    if High(par)>1 then begin
      save_lst(' ');
      justuj;
      put_lst(t+zm);
    end;

    for _odd:=0 to High(par)-1 do begin
     txt:=par[_odd];

     k:=1;  ety:=get_lab(k, txt, false);   // sprawdzamy czy etykieta posiada poprawne znaki
     if ety='' then blad(zm,8,txt[1]);   // pierwszy znak etykiety jest niewlasciwy

     if txt[k]='=' then begin
       str:=copy(txt,k+1,length(txt));

       enum.val:=oblicz_wartosc(str,zm);
     end else
      if not(test_char(k,txt)) then blad(zm,8,txt[k]);  // wystapil niedozwolony znak


     label_type:='C';

     branch:=true;                         // dla etykiet .ENUM nie ma relokowalnosci

     save_lab(ety, enum.val, bank, zm);

     bez_lst:=true;

     if enum.val>enum.max then enum.max:=enum.val;    // MAX dla okreslenia rozmiaru ENUM

     nul.i:=integer( enum.val );
     save_lst('l');

     if High(par)=1 then
      zapisz_lst(zm)
     else
      zapisz_lst(ety);

     inc(enum.val);
    end;

    dreloc.use := old_case;

    nul.i:=0;

    ety:='';
   end;


(*----------------------------------------------------------------------------*)
(*  dodatkowy test dla etykiet w bloku .STRUCT                                *)
(*----------------------------------------------------------------------------*)
  if struct.use then
   if (ety<>'') and (mne.l=0) then begin

    txt:=par[0];
    idx:=load_lab(txt, true);           // etykieta typu na poczatku

    if idx>=0 then
     if not((t_lab[idx].bnk=__id_struct) or (t_lab[idx].bnk=__id_enum)) then idx:=-1;

    if idx<0 then begin                 // lub na koncu wiersza
     txt:=par[High(par)-1];
     idx:=load_lab(txt, true);
    end else
     for k:=1 to High(par)-1 do par[k-1]:=par[k];

    ety:=par[0];
    SetLength(par, High(par));

    if idx<0 then begin
     if pass=pass_end then blad(zm,58)
    end else
     if t_lab[idx].bnk=__id_struct then begin
       mne.l := __struct_run_noLabel;
       mne.i := t_lab[idx].adr;
     end else
      if t_lab[idx].bnk=__id_enum then begin
       mne.l:=__byteValue+t_lab[idx].adr;
      end else
       if pass=pass_end then blad(zm,58);

   end;


JUMP_2:

(*----------------------------------------------------------------------------*)
(*  .END, #END                                                                *)
(*  zastepuje inne dyrektywy .END?                                            *)
(*----------------------------------------------------------------------------*)
 if macro_rept_if_test and (mne.l=__dend) then
  if end_idx=0 then
   blad(zm,72)
  else
   mne.l:=t_end[end_idx-1].kod;


(*----------------------------------------------------------------------------*)
(*  specjalna forma definicji wartosci etykiety tymczasowej za pomoca znakow  *)
(*  '=' , '+=' , '-=' , '++' , '--'                                           *)
(*----------------------------------------------------------------------------*)
 if mne.l in [__addEqu, __addSet] then begin

  if ety<>'' then save_lab(ety,adres,bank,zm);   // etykieta przed inna etykieta

  ety:=get_lab(i,zm, true);

  omin_spacje(i,zm);

  tmpZM:=zm;

  if UpCase(zm[i]) in ['E', 'S'] then
   inc(i,2)
  else
   if zm[i] in ['+','-'] then operator_zlozony(i,zm,ety, false);

  __inc(i,zm);
 end;


(*----------------------------------------------------------------------------*)
(*  laczenie mnemonikow za pomoca znaku ':', w stylu XASM'a                   *)
(*----------------------------------------------------------------------------*)
  if mne.l=__xasm then begin

   save_lab(ety,adres,bank,zm);

   if (pass=pass_end) and skip_use then warning(98);    // Skipping only the first instruction

   save_lst('a');

   loop_used := true;

   old_case  := case_used;            // nie mozemy zamieniac na duze litery
   case_used := true;                 // zachowujemy ich oryginalna wielkosc (CASE_USED=TRUE)

   skip_hlt  := true;

   xasmStyle:=true;


   k:=mne.i;
   ety:=get_dat(k,zm,'\',false);      // odczytujemy argumenty

   case_used := old_case;             // przywracamy stara wartosc CASE_USED

   line_add:=line-1;                  // numer linii aktualnie przetwarzanej
                                      // przyda sie jesli wystapi blad

   idx:=High(t_mac);                  // indeks do wolnego wpisu w T_MAC

   while true do begin                // petla bez konca ;)

    old_case  := case_used;           // tutaj takze musimy zachowac wielkosc liter
    case_used := true;                // dlatego wymuszamy CASE_USED=TRUE

    txt:=get_dat(i,zm,':',true);      // odczytujemy mnemonik rozdzielony znakiem ':'

    case_used := old_case;            // przywracamy stara wartosc CASE_USED

      str:=' '+txt+ety;               // preparujemy nowa linie do analizy
      t_mac[idx]:=str;                // zapisujemy ja w T_MAC[IDX]

      test_skipa;

      _odd := idx+1;
      analizuj_mem(idx,_odd, zm,a,old_str, 0,1, false);

    if zm[i]=':' then inc(i) else Break;   // tutaj konczymy petle jesli brak ':'
   end;


   xasmStyle:=false;

   wymus_zapis_lst(zm);

   line_add:=0;                       // koniecznie zerujemy LINE_ADD

   if not(FOX_ripit) then bez_lst   := true;

   loop_used := false;

   skip_hlt  := false;

   skip_xsm  := true;                 // wystapilo laczenie mnemonikow przez ':'

   mne.l:=__nill;
   ety:='';
  end else
   if not(mne.l in [0,__nill]) then skip_xsm:=false;    // nie wystapilo laczenie mnemonikow przez ':'  (default)


JUMP:

(*----------------------------------------------------------------------------*)
(*  jesli mamy uruchomione makro to zapisz jego zawartosc do pliku LST        *)
(*  puste linie nie sa zapisywane, !!! w tej postaci dziala najlepiej !!!     *)
(*----------------------------------------------------------------------------*)
  if run_macro and if_test then
   if ety<>'' then data_out:=true;


(*----------------------------------------------------------------------------*)
(* dla blokow SEGMENT sprawdzamy czy kod przekroczyl granice segmentu         *)
(*----------------------------------------------------------------------------*)
 if (segment>0) and macro_rept_if_test and (org_ofset=0) then
  if (adres<t_seg[segment].start) or (adres>t_seg[segment].start+t_seg[segment].len) then blad_und(zm,t_seg[segment].lab,104);


(*----------------------------------------------------------------------------*)
(*  BLK (kody __blkSpa, __blkRel, __blkEmp)                                   *)
(*----------------------------------------------------------------------------*)
 if mne.l=__blk then
 if ety<>'' then blad(zm,38) else
 if loop_used then blad(zm,36) else begin

  empty:=false;

  txt:=get_datUp(i,zm,#0,true);

  case UpCase(txt[1]) of
  //BLK D[os] a
  'D': mne.l := __org;

  //BLK S[parta] a
  'S': mne.l := __blkSpa;

  //BLK R[eloc] M[ain]|E[xtended]
  'R': mne.l := __blkRel;

  //BLK E[mpty] a M[ain]|E[xtended]
  'E': begin mne.l := __blkEmp; empty:=true end;

  //BLK N[one] a
  'N': begin mne.l := __org;  opt_h_minus end;

  //BLK U[pdate] A[ddress]
  //BLK U[pdate] E[xternal]
  //BLK U[pdate] S[ymbols]
  //BLK U[pdate] N[ew] address text
  'U':
    if pass=pass_end then begin

     oddaj_var;

     oddaj_ds;

     txt:=get_datUp(i,zm,#0,true);

     save_lst('a');

     _doo:=0;    // liczba adresow do relokacji
     _odd:=0;    // liczba symboli do relokacji

     for idx:=0 to rel_idx-1 do
      if t_rel[idx].idx>=0 then inc(_odd) else
       if t_rel[idx].idx=-1 then inc(_doo);

     case UpCase(txt[1]) of

      'A': begin                       // A[ddress]
            if not(blkupd.adr) then
             if (_doo>0) or dreloc.use then blk_update_address(zm);
            blkupd.adr:=true;
           end;

      'E': begin                       // E[xternal]
            if not(blkupd.ext) then blk_update_external(zm);
            blkupd.ext:=true;
           end;

      'P': begin                       // P[ublic]
            if not(blkupd.pub) then blk_update_public(zm);
            blkupd.pub:=true;
           end;

      'S': begin                       // S[ymbol]
            if not(blkupd.sym) then
             if _odd>0 then blk_update_symbol(zm);
            blkupd.sym:=true;
           end;

      'N': begin                       // N[ew]
            test_symbols := true;
            blk_update_new(i,zm);
           end;

     else
      blad(zm,23);
     end;

    end;

  else
   blad(zm,0);
  end;

 end;


(*----------------------------------------------------------------------------*)
(*  [label] .DS expression | .DS [elements0] [elements1] [...]                *)
(*  rezerwujemy "expression" bajtow bez ich inicjalizowania                   *)
(*----------------------------------------------------------------------------*)
 if (mne.l=__ds) and (macro_rept_if_test) then begin

   if struct.use or aray or enum.use then blad(zm,58);

 // po zmianie adresu asemblacji bloku .PROC, .LOCAL nie ma możliwosci używania dyrektywy .DS

   if (org_ofset>0) then blad(zm,71);

   nul.i:=integer( adres );
   save_lst('l');

   branch:=true;

   omin_spacje(i,zm);

   etyArray:=ety;

   _doo:=integer( oblicz_wartosc_noSPC(zm,zm,i,#0,'A') );

   if etyArray<>'' then                   // nie bylo .ARRAY
    save_lab(ety,adres,bank,zm);          // .DS expression

   if dreloc.sdx or dreloc.use then begin

    if (dreloc.sdx and (blok = 0)) {or dreloc.use} then begin // gdy BLOK = 0 (blk sparta) nie ma relokowalnosci

     for idx := 0 to _doo - 1 do save_dst(0);

    end else begin
     empty := true;
     inc(ds_empty, _doo);
    end;

    inc(adres, _doo);

   end else begin

    data_out:=true;

    txt:=zm;                   // !!! tylko tutaj wymuszamy zapis do LST !!!
    zapisz_lst(txt);

    NoAllocVar:=true;          // dla .DS nie ma alokacji zmiennych .VAR
    mne.l:=__org;              // teraz mozemy wymusic ORG *+

    zm:='*+'+IntToStr(_doo);
    i:=1;

    bez_lst:=true;
   end;

   ety:='';
 end;


(*----------------------------------------------------------------------------*)
(*  [label] .ALIGN N[,fill]                                                   *)
(*----------------------------------------------------------------------------*)
 if (mne.l=__align) and (macro_rept_if_test) then begin

  if loop_used then blad(zm,36);

  save_lst('a');

  omin_spacje(i,zm);

  if test_char(i,zm) then
   _doo:=$100
  else
   _doo:=integer( oblicz_wartosc_noSPC(zm,zm,i,',','A') );


  _odd:=-1;

  if zm[i]=',' then begin
   __inc(i,zm);

   _odd:=integer( oblicz_wartosc_noSPC(zm,zm,i,',','B') );
  end;


  if _doo>0 then
   idx:=(adres div _doo)*_doo
  else
   idx:=adres;

  if idx<>adres then inc(idx, _doo);


  if _odd>=0 then begin

   if pass=pass_end then begin
    while idx>adres do begin save_dst(byte(_odd)); inc(adres) end;
   end else
    adres:=idx;

  end else begin                     // wymuszenie ORG

   justuj;
   put_lst(t+zm);

   bez_lst:=true;

   zm:='$'+hex(idx,4);

   NoAllocVar:=true;                // dla .ALIGN nie ma alokacji zmiennych .VAR
   mne.l:=__org;

   i:=1;
  end;

 end;


(*----------------------------------------------------------------------------*)
(*  NMB [adres]                                                               *)
(*  RMB [adres]                                                               *)
(*  LMB #expression [,adres]                                                  *)
(*----------------------------------------------------------------------------*)
 if macro_rept_if_test then begin

  ch:=' ';              // CH bedzie zawieral znak dyrektywy 'N'MB, 'R'MB, 'L'MB

  case mne.l of

   __nmb: begin
           inc(bank);   // zwiekszamy licznik bankow MADS'a

           ch:='N';
          end;

   __rmb: begin
           bank:=0;     // zerujemy licznik bankow MADS'a

           ch:='R';
          end;

   __lmb: begin         // ustawiamy licznik bankow MADS'a
           omin_spacje(i,zm);
//           if zm[i] in ['<','>'] then else                  // znaki '<', '>' sa akceptowane
           if zm[i]<>'#' then blad(zm,14) else __inc(i,zm); // pozostale znaki inne niz '#' to blad

           txt:=get_dat_noSPC(i,zm,zm,' ');
           k:=1; j:=integer( oblicz_wartosc_noSPC(txt,zm,k,',','B') );  // wartosc licznika bankow = 0..255

           bank:=integer( j );

           ch:='L';
          end;

  end;

(*----------------------------------------------------------------------------*)
(*  wymuszamy wykonanie makra @BANK_ADD (gdy OPT B+) dla LMB, NMB, RMB        *)
(*----------------------------------------------------------------------------*)
 if ch<>' ' then begin

  if dreloc.use or dreloc.sdx then blad(zm,71);
  if first_org then blad(zm,10);

  save_lst('i');

  if opt and opt_B>0 then begin

   omin_spacje(i,zm);
   if zm[i]=',' then __inc(i,zm);

   str:=get_dat_noSPC(i,zm,zm,' ');
   if str<>'' then str:=','+str;

   wymus_zapis_lst(zm);

   txt:='@BANK_ADD '''+ch+''''+str;
   i:=1; mne:=oblicz_mnemonik(i,txt,zm);
   zm:=txt;
  end;

 end;

 end;


(*----------------------------------------------------------------------------*)
(*  wykonaj .PROC gdy PASS>0                                                  *)
(*  wymus wykonanie makra @CALL jesli procedura miala parametry               *)
(*  jesli procedura zostaje wywolana z poziomu innej procedury zapamietaj     *)
(*  parametry procedury na stosie nie modyfikujac wskaznika stosu,            *)
(*  a po powrocie przywroc je takze nie modyfikujac wskaznika stosu           *)
(*----------------------------------------------------------------------------*)
  if mne.l=__proc_run then
   if macro_rept_if_test then begin

    save_lab(ety,adres,bank,zm);

    indeks:=mne.i;

    idx:=t_prc[indeks].par;          // liczba parametrow

    tlin := t_lin;

    if idx>0 then begin

     wymus_zapis_lst(zm);

     ety:='';
     str:='';


   // jesli nastepuje wywolanie procedury typu T_PRC[].TYP=__pDef, ktora posiada parametry (IDX>0)
   // z ciala aktualnie przetwarzanej procedury PROC_NR-1
   // to odlozymy na stos parametry procedury aktualnej, a po powrocie przywrocimy je

     if proc and (t_prc[indeks].typ=__pDef) then begin
      _doo:=t_prc[proc_nr-1].ile;                     // liczba bajtow przypadajaca na parametry

      if _doo>0 then begin
       //str:=copy(proc_name,1,length(proc_name)-1);  // obcinamy ostatnia kropke w nazwie aktualnej procedury
       str:=proc_name;
       SetLength(str,length(proc_name)-1);

       ety:=' @PUSH ''I'','+IntToStr(_doo)+' \ ';
       str:=' \ @PULL ''J'','+IntToStr(_doo);
      end;

     end;


     rodzaj := t_prc[indeks].typ;  // rodzaj procedury, sposobu przekazywania parametrow

     get_parameters(i,zm,par,false, #0,':');   // znak kropki musi akceptowac dla .LEN, .SIZEOF itp.


     // sprawdzamy liczbe przekazanych parametrow, jesli ich liczba sie nie zgadza to
     // wystapi blad 'Improper number of actual parameters'
     // w przypadku procedur typu __pReg, __pVar moze byc mniej parametrow, ale nie wiecej

       _doo:=High(par);

       for _odd:=_doo-1 downto 0 do begin

        txt:=par[_odd];

        if txt='' then
         if rodzaj=__pDef then
          blad(zm,40)
         else
          txt:=';';                       // dla __pReg mozemy pomijac parametry

        if (txt[1]='"') and (length(txt)>2) then txt:=copy(txt,2,length(txt)-2);

        par[_odd]:=txt;
       end;


     // sprawdz typ parametrow i wymus wykonanie makra @CALL_INIT, @CALL, @CALL_END
     // parametrem @CALL_INIT jest liczba bajtow zajmowanych przez parametry procedury

       case rodzaj of
     __pDef: begin
              if _doo<>idx then blad(zm,40);
              ety:=ety+' @CALL '+#39+'I'+#39+','+IntToStr(t_prc[indeks].ile);
             end;

     __pReg, __pVar:
             begin
              if _doo>idx then
               blad(zm,40)
              else
               if (pass=pass_end) and (_doo<idx) then warning(40);

              ety:=ety+' ';
             end;
       end;


       idx:=t_prc[indeks].str;       // indeks do nazw parametrow w T_PAR


      if _doo>0 then
       for k:=0 to _doo-1 do
        if par[k][1]<>';' then begin

         txt:=par[k];

         case rodzaj of
          __pDef: ety:=ety+' \ @CALL ';
         end;

         ch:=' ';
         v:=byte(' ');

         if txt='@' then begin
//          ety:=ety+#39+'@'+#39+',';
          v:=byte('@');
          war:=0;
          ch:='Z';
         end else
          if txt[1]='#' then begin
//           ety:=ety+#39+'#'+#39+',';
           v:=byte('#');
           branch:=true;
           tmp:=copy(txt,2,length(txt));
           war:=oblicz_wartosc(tmp,zm);
           ch:=value_code(war,zm,true);
          end;

       // typ parametru w deklaracji procedury (B,W,L,D)
       // funkcja VALUE_CODE zwrocila typ parametru (Z,Q,T,D)
        tmpZM:=copy(t_par[idx+k],2,length(t_par[idx+k]));

        if pass>0 then

         if ch<>' ' then
           case t_par[idx+k][1] of
            'B': if ch<>'Z' then blad_und(zm,tmpZM,41);
            'W': if (ch in ['T','D']) or (txt='@') then blad_und(zm,tmpZM,41);
           end;


     if rodzaj<>__pVar then
      if txt[1]='#' then txt[1]:=' ';


     case rodzaj of
       __pDef: ety:=ety+#39+chr(v)+#39+',';

       __pReg: case chr(v) of
                '#': case t_par[idx+k][1] of     // przez wartosc
                      'B': ety:=ety+'LD'+t_par[idx+k][2]+'#'+txt;
                      'W': ety:=ety+'LD'+t_par[idx+k][2]+'>'+txt + '\ LD'+t_par[idx+k][3]+'<'+txt;
                      'L': ety:=ety+'LD'+t_par[idx+k][2]+'^'+txt + '\ LD'+t_par[idx+k][3]+'>'+txt + '\ LD'+t_par[idx+k][4]+'<'+txt;
                     end;

                ' ': case t_par[idx+k][1] of     // przez adres
                      'B': ety:=ety+'LD'+t_par[idx+k][2]+' '+txt;
                      'W': ety:=ety+'LD'+t_par[idx+k][2]+' '+txt + '+1\ LD'+t_par[idx+k][3]+' '+txt;
                      'L': begin
                            ety:=ety+'LD'+t_par[idx+k][2]+' '+txt + '+2\ LD'+t_par[idx+k][3]+' '+txt + '+1\ LD'+t_par[idx+k][4]+' '+txt;
                            if dreloc.use then warning(86);    // typ 'L' nie jest relokowalny
                           end;
                     end;

                '@': if t_par[idx+k][2]<>'A' then ety:=ety+'TA'+t_par[idx+k][2];
               end;

       __pVar: case chr(v) of
                '#',' ': case t_par[idx+k][1] of      // przez wartosc '#' lub wartosc spod adresu ' '
                          'B': ety:=ety+'MVA '+txt+' '+tmpZM;
                          'W': ety:=ety+'MWA '+txt+' '+tmpZM;
                          'L': case chr(v) of
                                '#': begin
                                      txt[1]:='(';  txt:='#'+txt+')';
                                      ety:=ety+' MWA '+txt+'&$FFFF '+tmpZM+'\';
                                      ety:=ety+' MVA '+txt+'>>16 '+tmpZM+'+2\';
                                     end;

                                ' ': begin
                                      ety:=ety+' MWA '+txt+' '+tmpZM+'\';
                                      ety:=ety+' MVA '+txt+'+2 '+tmpZM+'+2';
                                     end;
                               end;
                          'D': case chr(v) of
                                '#': begin
                                      txt[1]:='(';  txt:='#'+txt+')';
                                      ety:=ety+' MWA '+txt+'&$FFFF '+tmpZM+'\';
                                      ety:=ety+' MWA '+txt+'>>16 '+tmpZM+'+2\';
                                     end;

                                ' ': begin
                                      ety:=ety+' MWA '+txt+' '+tmpZM+'\';
                                      ety:=ety+' MWA '+txt+'+2 '+tmpZM+'+2';
                                     end;
                               end;
                         end;

                    '@': ety:=ety+'STA '+tmpZM;
               end;
     end;


         if rodzaj=__pDef then begin
          ety:=ety+#39+t_par[idx+k][1]+#39+',';
          if txt[1] = '@' then ety:=ety+'0' else ety:=ety+'"'+txt+'"';
         end else ety:=ety+'\ ';

        end;

     if rodzaj=__pDef then
      txt:=ety+' \ @CALL '+#39+'X'+#39+','+t_prc[indeks].nam + ' \ @EXIT '+IntToStr(t_prc[indeks].ile) + str
     else
      txt:=ety+'JSR '+t_prc[indeks].nam;

     k:=line_add;

     line_add:=line-1;

     _odd:=High(t_mac);                      // procedura z parametrami
     t_mac[_odd]:=txt;                       // wymuszamy wykonanie większej liczby linii
     _doo:=_odd+1;
     analizuj_mem(_odd,_doo, zm,a,old_str, 0,1, false);

     line_add:=k;

     bez_lst:=true;

    end else begin
     txt:='JSR '+ t_prc[indeks].nam;         // procedura bez parametrow
     i:=1; mne:=oblicz_mnemonik(i,txt,zm);   // wymuszamy wykonanie jednej linii z JSR
    end;

     t_lin := tlin;
     SetLength(tlin, 0);

     ety:='';
    end;


(*----------------------------------------------------------------------------*)
(*  .ERROR [ERT] 'text' | .ERROR [ERT] expression                             *)
(*----------------------------------------------------------------------------*)
   if (mne.l in [__error,__ert]) and macro_rept_if_test then
     if pass=pass_end then begin

        save_lst(' ');

	txt:='';

        txt:=get_string(i,zm,txt,true);

        if txt<>'' then begin

         if not(run_macro) then
          writeln(zm)
         else
          writeln(old_str);

         str:=end_string;  end_string:='';

         wypisz(i,zm);               // !!! modyfikowana jest zmienna ZM !!!

         txt:=txt+end_string;

         end_string:=str;

         blad(txt,34);

        end else begin

          branch := true;             // tutaj nie ma mowy o relokowalnosci
          war:=oblicz_wartosc_noSPC(zm,zm,i,',','F');

          if war<>0 then begin

           if not(run_macro) then
            writeln(zm)
           else
            writeln(old_str);

           str:=end_string;  end_string:='';

           wypisz(i,zm);             // !!! modyfikowana jest zmienna ZM !!!

           if end_string='' then
            txt:=load_mes(30+1)      // User error
           else
            txt:=end_string;

           end_string:=str;

           blad(txt,34);
          end;

        end;

      end else
       mne.l:=__nill;


(*----------------------------------------------------------------------------*)
(*  .EXIT                                                                     *)
(*----------------------------------------------------------------------------*)
  if (mne.l=__exit) and macro_rept_if_test then
    if not(run_macro) then blad(zm,58) else begin

     save_lab(ety,adres,bank,zm);
     save_lst(' ');

     wymus_zapis_lst(zm);

     run_macro:=false;

     wyjscie:=true;

     ety:='';

     exit;
    end;


(*----------------------------------------------------------------------------*)
(*  .ENDP                                                                     *)
(*----------------------------------------------------------------------------*)
  if (mne.l=__endp) and macro_rept_if_test then
     if ety<>'' then blad(zm,38) else
      if not(proc) then blad(zm,39) else begin

       save_lst(' ');

       oddaj_var;

       oddaj_lokal(zm);

       t_prc[proc_nr-1].len := cardinal(adres) - t_prc[proc_nr-1].adr;


       proc_nr := t_prc[proc_nr-1].pnr;   // !!! koniecznie ta kolejnosc inaczej zawsze PROC_NR=0 !!!

       get_address_update;

       proc      := t_prc[proc_nr].prc;
       org_ofset := t_prc[proc_nr].oof;
       proc_name := t_prc[proc_nr].pnm;

      end;


(*----------------------------------------------------------------------------*)
(*  label .PROC [label]                                                       *)
(*  jesli wystepuja parametry ograniczone nawiasami '()' to zapamietaj je     *)
(*----------------------------------------------------------------------------*)
  if (mne.l=__proc) and macro_rept_if_test then
   if adres<0 then blad(zm,10) else
         begin

          if ety='' then ety:=get_lab(i,zm, true);

          save_lst('a');
          txt:=zm; zapisz_lst(txt);
          bez_lst:=true;

          label_type:='P';

          if not(proc) then
           ety:=lokal_name+ety
          else
           ety:=proc_name+ety;

          zapisz_lokal;
          lokal_name:='';


          t_prc[proc_idx].prc := proc;
          t_prc[proc_idx].pnr := proc_nr;
          t_prc[proc_idx].oof := org_ofset;
          t_prc[proc_idx].pnm := proc_name;

          proc_nr:=proc_idx;     // koniecznie przez ADD_PROC_NR


          get_address(i,zm);     // pobieramy nowy adres asemblacji dla .PROC


          save_end(__endp);


          proc_lokal:=end_idx;   // koniecznie po SAVE_END, nie wczesniej

          save_lst('a');  proc_name:='';

          if (pass=pass_end) and not(exclude_proc) and not(dreloc.use) then
           if not(t_prc[proc_nr].use) then blad_und(zm,ety,69);


          txt:=zm;   // jesli TXT<>ZM to UPD_PROCEDURE zmodyfikowala ZM jakims makrem


          if t_prc[proc_nr].nam='' then       // 'if pass=0' moze zostac pominiete jesli PROC jest w blokach IF
           get_procedure(ety,ety,zm ,i)       // zapamietujemy parametry procedury
          else
           upd_procedure(ety,zm,adres);       // uaktualniamy adresy procedury


          add_proc_nr;                        // nowa wartosc PROC_NR, PROC_IDX


          if (txt<>zm) and proc {and (pass>0)} then begin
            save_lst(' ');
            i:=1; mne:=oblicz_mnemonik(i,zm,zm);
          end;

          if pass_end<3 then pass_end:=3;     // dla szczegolnych przypadkow 2 przebiegi to za malo (JAC!)

          proc      := true;

          proc_name := ety+'.';

          ety:=''
         end;


(*----------------------------------------------------------------------------*)
(*  wykonaj .STRUCT (np. deklaracja pola struktury za pomoca innej struktury) *)
(*  możliwe jest przypisanie pol zdefiniowanych przez strukture nowej zmiennej*)
(*----------------------------------------------------------------------------*)
  if mne.l in [__struct_run, __struct_run_noLabel, __enum_run] then
   if ety='' then blad(zm,15) else
    if macro_rept_if_test then begin

     if (mne.l=__enum_run) and struct.use then

      mne.l:=__byteValue+mne.i                // typ wyliczeniowy na rozmiar w bajtach

     else begin

      if High(par)<1 then
       create_struct_variable(zm, ety, mne, true, adres)
      else
       for k := 0 to High(par)-1 do begin
        ety:=par[k];
        create_struct_variable(zm, ety, mne, true, adres);
       end;

      mne.l := __nill;

      ety:='';
     end;

    end;

(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)


  case mne.l of

(*----------------------------------------------------------------------------*)
(*  wykonaj .MACRO gdy PASS>0                                                 *)
(*----------------------------------------------------------------------------*)
  __macro_run:
//        if macro then halt {inc(macro_nr)} else
        if if_test then begin

         save_lab(ety,adres,bank,zm);

         if not(FOX_ripit) then save_lst('i');

         txt:=zm;
         zapisz_lst(txt);

         indeks:=mne.i;

         old_komentarz:=komentarz;

       // zapamietujemy aktualne makro w 'OLD_MACRO_NR'

         old_macro_nr:=macro_nr;

         txt:=t_mac[indeks+1];

       // !!! nazwa obszaru LOCAL powtorzy sie 2x - KONIECZNIE !!!
         if macro_nr='' then
          macro_nr:=macro_nr+lokal_name+proc_name+txt+t_mac[indeks+3]+'.'
         else
          macro_nr:=macro_nr+proc_name+txt+t_mac[indeks+3]+'.';

         omin_spacje(i,zm);  SetLength(par,2);
        // na pozycji par[0] zostanie wpisana liczba parametrow

         k:=ord(t_mac[indeks+2][1]);      // tryb pracy
         ch:=t_mac[indeks+2][2];          // separator


         while not(test_char(i,zm)) do begin

          txt:=get_dat(i,zm,ch,true);

        // jesli to licznik petli FOX_RIPIT '#' (lub .R) to wyliczymy wartosc
          if (txt='#') or (txt='.R') then begin
            war:=oblicz_wartosc(txt,zm);
            txt:=IntToStr(war);
          end;

        // jesli przekazywany parametr jest miedzy apostrofami " " to jest to ciag znakowy
          if txt<>'' then
           if (txt[1]='"') and (txt[length(txt)]='"') then txt:=copy(txt,2,length(txt)-2);

          _odd:=High(par);

          if k=byte('''') then begin
           par[_odd]:=txt;
           SetLength(par,_odd+2);
          end else begin

            if txt[1]='#' then begin
             par[_odd]:='''#''';
             txt:=copy(txt,2,length(txt));
            end else
             if txt[1] in ['<','>'] then begin
              par[_odd]:='''#''';
              war:=oblicz_wartosc(txt,zm);
              txt:=IntToStr(war);
             end else par[_odd]:=''' ''';

           SetLength(par,_odd+3);
           par[_odd+1]:=txt;
          end;

//          omin_spacje(i,zm);
          if zm[i] in [',',' ',#9] then __next(i,zm);

           if ch<>' ' then
            if zm[i]=ch then __inc(i,zm); // else Break;

         end;

        // zapisujemy liczbe parametrow dla :0
         par[0]:=IntToStr(Int64(High(par))-1);


         // zwiekszamy numer wywolania makra T_MAC[indeks+3], T_MAC[indeks+5]
         // !!! koniecznie w tym miejscu !!!

         _doo:=integer( StrToInt(t_mac[indeks+3]) );
         t_mac[indeks+3]:=IntToStr(Int64(_doo)+1);

         _doo:=integer( StrToInt(t_mac[indeks+5]) );
         t_mac[indeks+5]:=IntToStr(Int64(_doo)+1);

         // !!! zabezpieczenie przed rekurencja bez konca !!!
         // zatrzymujemy wykonanie makra jesli liczba wywolan przekroczy 255

         if _doo>255 then blad(zm,66);


         _doo:=integer( StrToInt(t_mac[indeks+4]) );  // numer linii

         txt:=t_mac[indeks];       // nazwa pliku z aktualnie wykonywanym makrem

         inc(wyw_idx);
         if wyw_idx>High(t_wyw) then SetLength(t_wyw,wyw_idx+1);

         t_wyw[wyw_idx].zm := zm;  // jesli wystapi blad to te dane pomoga go zlokalizowac
         t_wyw[wyw_idx].pl := txt;
         t_wyw[wyw_idx].nr := _doo;


        // zapamietujemy aktualny indeks do T_MAC w _ODD
        // odczytujemy makro z T_MAC[indeks], podstawiamy parametry i zapisujemy do T_MAC
        // potem zwolnimy miejsce na podstawie wczesniej zapamietanego indeksu w _ODD

         _odd:=High(t_mac);

         tmp:=t_mac[indeks+1];        // nazwa makra potrzebna do parametrow z nazwami

         while true do begin
          txt:=t_mac[indeks+6];

          j:=1;

          ety:=get_datUp(j,txt,#0,false);  // wczytujemy nieznany ciag duzych liter

          if not(fCRC16(ety)=__endm) then begin  // aby odnalezc wpis .ENDM, .MEND

           j:=1;
           while j<=length(txt) do
            if test_macro_param(j,txt) then begin

             k:=j;
             if txt[j]=':' then begin
              inc(j);
              typ:=':';                     // parametr przez :
             end else begin
              inc(j,2);
              typ:='%';                     // parametr przez %%
             end;


             ety:='';

             if _dec(txt[j]) then
              ety:=read_DEC(j, txt)
             else
              while _mpar(txt[j]) do begin ety:=ety+UpCas_(txt[j]); inc(j) end;


             if _mpar_alpha(ety[1]) then begin
              str:=tmp+'.'+ety;

              while (l_lab(str)<0) and (ety<>'') do begin

               SetLength(str, length(str)-1);
               SetLength(ety, length(ety)-1);

               dec(j);
              end;

              war:=l_lab(str);

              if war>=0 then
               if t_lab[war].bnk=__id_mparam then
                war:=t_lab[war].adr
               else
                war:=-1;

//              if (pass=pass_end) and (war<0) and (typ='%') then blad_und(zm, ety, 5);

             end else
              war:=StrToInt(ety);


             if war>=0 then begin

              delete(txt,k,j-k);  dec(j,j-k);

              if war>Int64(High(par))-1 then begin
               insert('$FFFFFFFF',txt,k); inc(j,9);   // musi koniecznie wpisac ciag $FFFFFFFF
              end else begin
               insert(par[war],txt,k);
               inc(j,length(par[war]));
              end;

             end;

            end else inc(j);

           save_mac(txt);
          end else Break;

          inc(indeks);
         end;


         str:='Macro: '+t_mac[mne.i+1]+' [Source: '+t_mac[mne.i]+']';

         if not(FOX_ripit) and not(rept_run) then put_lst(str);

        // zapamietaj w zmiennych lokalnych

         indeks          := line_add;
         line_add        := 0;

         old_rept        := ___rept_ile;

         par             := reptPar;

         old_case        := rept_run;
         rept_run        := false;

         old_run_macro   := run_macro;
         old_ifelse      := ifelse;
         old_loopused    := loop_used;

         old_trep        := t_rep;

         SetLength(t_rep, 1);

         old_rept_cnt    := rept_cnt;
         rept_cnt        := 0;

         komentarz := old_komentarz;

         run_macro := true;

         loop_used := false;

         _doo:=High(t_mac);

//         for idx:=_odd to _doo-1 do writeln(t_mac[idx],' | '); halt;

         analizuj_mem(_odd,_doo, zm,a,old_str, idx,idx+1, false);

         if not(FOX_ripit) then bez_lst:=true;


         if run_macro and (old_ifelse<>ifelse) then blad(zm,1);


         run_macro   := old_run_macro;

         t_mac[mne.i+5]:='0';


         loop_used   := old_loopused;

         rept_run    := old_case;

         ifelse      := old_ifelse;
         macro_nr    := old_macro_nr;

         ___rept_ile := old_rept;

         reptPar     := par;

         t_rep       := old_trep;
         rept_cnt    := old_rept_cnt;

         line_add    := indeks;


         if not(lst_off) and not(FOX_ripit) and not(rept_run) then put_lst(show_full_name(a,full_name,true));

         dec(wyw_idx);

         SetLength(t_mac,_odd+1);

         ety:='';
        end;


(*----------------------------------------------------------------------------*)
(*  label .DEFINE [label] expr                                                *)
(*  jednoliniowe makro                                                        *)
(*----------------------------------------------------------------------------*)
   __define:
         begin
          if ety='' then ety:=get_lab(i,zm, true);

          if {(pass=0) and} if_test then begin  // .DEFINE mozna zmieniac w tym samym przebiegu

           //reserved_word(ety,zm);

           k := load_lab(ety,true);

           idx := High(t_mac);

           if k >= 0 then begin

            idx := t_lab[k].adr;                // nadpisujemy makro .DEFINE

           end else begin
            save_lab(ety, idx, __id_define,zm); // rezerwuj nowe miejsce w t_mac

            save_mac('');
            save_mac('');
            save_mac('');

           end;

           omin_spacje(i,zm);

           t_mac[idx] := ety;                   // nazwa makra

           tmp:=copy(zm, i, length(zm));

           if High(t_lin) > 0 then blad(zm, 123);

           // sprawdzamy obecnosc parametrow :x lub %%x (x od 0..9)

           for k := 9 downto 0 do
            if (pos('%%'+IntToStr(k), tmp) > 0) or (pos(':'+IntToStr(k), tmp) > 0) then Break;

           if k>0 then                          // liczba parametrow
            t_mac[idx+1] := IntToStr(k)
           else
            t_mac[idx+1] := '';

           t_mac[idx+2] := tmp;                 // regula

           if pass_end<3 then pass_end:=3;      // jesli sa makra to musza byc conajmniej 3 przebiegi
          end;

          save_lst(' ');

          ety:='';

         end;


(*----------------------------------------------------------------------------*)
(*  label .UNDEF [label]                                                      *)
(*----------------------------------------------------------------------------*)
   __undef:
         begin

 	  if ety='' then ety:=get_lab(i,zm, true);

	  if if_test then begin			// .UNDEF mozna zmieniac w tym samym przebiegu

            k := load_lab(ety,true);

            if (k >= 0) and (t_lab[k].bnk = __id_define) then begin

             idx := t_lab[k].adr;

	     if t_mac[idx][1] <> '~' then
 	      t_mac[idx] := '~' + t_mac[idx];	// zaznaczamy jako wylaczone

            end else
	     blad_und(zm,ety,35);

	  end;

	  save_lst(' ');

          ety:='';

         end;


(*----------------------------------------------------------------------------*)
(*  .LONGA|.LONGI ON/OFF						      *)
(*----------------------------------------------------------------------------*)
   __longa, __longi:
         if macro_rept_if_test then begin

	  if ety<>'' then save_lab(ety,adres,bank,zm);

	  omin_spacje(i, zm);

	  str := get_lab(i,zm, false);

	  if not(opt and opt_C>0) then blad(zm, 14);

	  if (str='') or ((str <> 'ON') and (str <> 'OFF')) then blad(zm, 58);

	  if (str='ON') or (str='16') then v:=16 else v:=8;

	  if mne.l = __longa then
	   longa := v
	  else
	   longi := v;

	  save_lst(' ');

	  ety:='';

	 end;


(*----------------------------------------------------------------------------*)
(*  .A8 ; .A16 ; .AI8 ; .AI16						      *)
(*----------------------------------------------------------------------------*)
   __a, __ai:
         if macro_rept_if_test then begin

	  if ety<>'' then save_lab(ety,adres,bank,zm);

	  if mne.l = __a then
	   ety := '.A'
	  else
	   ety := '.AI';

	  omin_spacje(i, zm);

	  str:=read_dec(i,zm);

	  if (str='8') or (str='16') then begin

	   if not(opt and opt_C>0) then blad(zm, 14);

	   if str='8' then
	    mne.h[0] := ord(SEP)
	   else
	    mne.h[0] := ord(REP);

	   if mne.l = __a then
            mne.h[1]:=$20
	   else
            mne.h[1]:=$30;

	  end else
           blad_und(a,ety+str,68);

	  reg_size(mne.h[1], t_MXinst(mne.h[0]) );

	  mne.l := 2;

	  //save_lst('a');

	  ety:='';

	 end;


(*----------------------------------------------------------------------------*)
(*  .I8 ; .I16 ; .IA8 ; .IA16						      *)
(*----------------------------------------------------------------------------*)
   __i, __ia:
         if macro_rept_if_test then begin

	  if ety<>'' then save_lab(ety,adres,bank,zm);

	  if mne.l = __i then
	   ety := '.I'
	  else
	   ety := '.IA';

	  omin_spacje(i, zm);

	  str:=read_dec(i,zm);

	  if (str='8') or (str='16') then begin

	   if not(opt and opt_C>0) then blad(zm, 14);

	   if str='8' then
	    mne.h[0] := ord(SEP)
	   else
	    mne.h[0] := ord(REP);

	   if mne.l = __i then
            mne.h[1]:=$10
	   else
            mne.h[1]:=$30;

	  end else
           blad_und(a,ety+str,68);

	  reg_size(mne.h[1], t_MXinst(mne.h[0]) );

	  mne.l := 2;

	  //save_lst('a');

	  ety:='';

	 end;


(*----------------------------------------------------------------------------*)
(*  label .MACRO [label] [par1, par2, ...]                                    *)
(*  wystapienie dyrektywy .MACRO oznacza conajmniej 3 przebiegi asemblacji    *)
(*----------------------------------------------------------------------------*)
   __macro:
         begin
          if ety='' then ety:=get_lab(i,zm, true);

          if (pass=0) and if_test then begin

// Konop postulowal aby przywrocic makra z blokow PROC
//           if proc then t_prc[proc_nr-1].use:=true;  // jesli makro w .PROC to takie .PROC zawsze w uzyciu

           reserved_word(ety,zm);
           save_lab(ety,High(t_mac),__id_macro,zm);

           str:=show_full_name(a,full_name,false);  save_mac(str);  // zapisanie nazwy pliku z makrem
//           str:={lokal_name+}ety;                   save_mac(str);  // zapisanie nazwy makra

           if proc then
            str:=proc_name+lokal_name+ety
           else
            str:=lokal_name+ety;

           save_mac(str);

           str:=ety;                          // czysta nazwa makra


           omin_spacje(i,zm);

           if zm[i] in AllowStringBrackets then
            tmp:=ciag_ograniczony(i,zm,true)
           else
            tmp:=get_dat(i,zm,#0,false);

           j:=1;
           get_parameters(j,tmp,par,true);


           ety:=''''; ch:=',';

           j:=1;                              // licznik parametrow

           for k := 0 to High(par)-1 do begin
            txt:=par[k];

            if txt[1] in AllowQuotes then begin
            // wczytujemy i sprawdzamy poprawnosc
             ety:=txt[1];
             if length(txt)>2 then ch:=txt[2];
            end else begin
             txt:=str+'.'+txt;

// makra rejestrujemy tylko w pierwszym przebiegu dlatego musimy "recznie"
// sprawdzic czy kolejny parametr nie jest dublowany

             if l_lab(txt)<0 then
              save_lab(txt, j, __id_mparam, zm)   // rejestrujemy parametr makra
             else
              blad_und(zm, txt, 2);

             inc(j);
            end;

           end;


           omin_spacje(i,zm);
           if not(test_char(i,zm)) then blad(zm,4);

           str:=ety+ch;         save_mac(str); // separator i tryb dzialania
           str:='0';            save_mac(str); // numer wywolania makra
           str:=IntToStr(line); save_mac(str); // numer linii z makrem

           str:='0';            save_mac(str); // licznik wywolan dla testu 'infinite loop'

           if pass_end<3 then pass_end:=3;     // jesli sa makra to musza byc conajmniej 3 przebiegi
          end;

          macro := true;

          save_lst(' ');

//          save_end(__endm);

          ety:=''
         end;

(*----------------------------------------------------------------------------*)
(*  .IF [IFT] expression                                                      *)
(*----------------------------------------------------------------------------*)
   __if, __ifndef, __ifdef:
         begin

           save_lab(ety,adres,bank,zm);

           txt:=zm;              // TXT = ZM, w celu pozniejszej modyfikacji TXT

           if mne.l in [__ifndef, __ifdef] then begin

             insert('.DEF',txt,i);

             if mne.l=__ifndef then insert('.NOT ',txt,i);

           end;

           if_stos[ifelse].old_iftest := if_test;


           inc(ifelse);
           if ifelse>High(if_stos) then SetLength(if_stos,ifelse+1);


           if_stos[ifelse]._okelse:=$7FFFFFFF;      // zablokowany .ELSE

           if if_test then begin
             save_lst(' ');

             if_stos[ifelse]._else   := false;

             if_stos[ifelse]._okelse := ifelse;

             branch := true;             // tutaj nie ma mowy o relokowalnosci
             war:=oblicz_wartosc_noSPC(txt,zm,i,#0,'F');

             if_test := (war<>0);
           end;

           if_stos[ifelse]._if_test := if_test;

          ety:='';
         end;

(*----------------------------------------------------------------------------*)
(*  .ENDIF [EIF]                                                              *)
(*----------------------------------------------------------------------------*)
   __endif:
       if ety<>'' then blad(zm,38) else
         if ifelse>0 then begin

           dec(ifelse);

//           if_test     := if_stos[ifelse]._if_test;
//           else_used   := if_stos[ifelse]._else;

           if_test := if_stos[ifelse].old_iftest;

         end else
          blad(zm,37);


(*----------------------------------------------------------------------------*)
(*  .ENDM                                                                     *)
(*----------------------------------------------------------------------------*)
   __endm: dec_end(zm, __endm);


(*----------------------------------------------------------------------------*)
(*  .ELSE [ELS]                                                               *)
(*----------------------------------------------------------------------------*)
   __else:
       if ety<>'' then blad(zm,38) else
         if if_stos[ifelse]._okelse=ifelse then begin

          if if_stos[ifelse]._else then blad(zm,1);
          if ifelse=0 then blad(zm,37);

          if_stos[ifelse]._else:=true;

          if_test := not(if_stos[ifelse]._if_test);
         end;

(*----------------------------------------------------------------------------*)
(*  .PRINT 'string' [,string2...] [,expression1,expression2...]               *)
(*----------------------------------------------------------------------------*)
   __print:
       if ety<>'' then blad(zm,38) else
        if macro_rept_if_test then
         if pass=pass_end then begin

          wypisz(i,zm);

         end;

(*----------------------------------------------------------------------------*)
(*  .ELSEIF [ELI] expression                                                  *)
(*----------------------------------------------------------------------------*)
   __elseif:
      if ety<>'' then blad(zm,38) else
       if if_stos[ifelse]._okelse=ifelse then begin	// !!! konieczny warunek

              if if_stos[ifelse]._else then blad(zm,1);
              if ifelse=0 then blad(zm,37);

              if_test := not(if_stos[ifelse]._if_test);

              if if_test then begin

                save_lst(' ');

                branch:=true;				// tutaj nie ma mowy o relokowalnosci
                war:=oblicz_wartosc_noSPC(zm,zm,i,#0,'F');

                if_test     := (war<>0);

                if_stos[ifelse]._if_test := if_test;	// !!! koniecznie zapisz IF_TEST
              end;

       end;

(*----------------------------------------------------------------------------*)
(*  label .LOCAL [label]                                                      *)
(*----------------------------------------------------------------------------*)
   __local:
        if macro_rept_if_test then begin

	  yes:=false;

          if ety='' then begin
           omin_spacje(i,zm);

	   if zm[i] = '+' then begin yes:=true; inc(i) end;

           ety:=get_lab(i,zm, false);
          end;


	  omin_spacje(i,zm);

        // jesli brak nazwy obszaru .LOCAL lub ',address' to przyjmij domyslna nazwe
          if (ety='') and (zm[i]<>',') then begin
           ety:=__local_name+IntToStr(lc_nr);
           inc(lc_nr);
          end;


	  if yes then begin

	   tmp:=lokal_name;
	   lokal_name:='';

           idx:=load_lab(ety, true);

	   lokal_name:=tmp;

	   if idx<0 then blad_und(zm,ety,5);

	   tmp:=lokal_name + ety;
           idx:=load_lab(tmp, true);

	   t_loc[lokal_nr].idx := idx;
           t_loc[lokal_nr].adr := adres;

           save_lst('a');

	   save_end(__endl);
	   zapisz_lokal;

           lokal_name := ety + '.';

           t_end[end_idx-1].adr:=0;
           t_end[end_idx-1].old:=0;

	  end else begin


          if pass=0 then if (ety<>'') and (ety[1]='?') then warning(8);


          t_loc[lokal_nr].ofs := org_ofset;

          get_address(i,zm);				// nowy adres asemblacji dla .LOCAL


          if not(test_char(i,zm)) then blad(zm,4);


          save_lab(ety, adres, bank, zm, true);

          save_lst('a');

          t_loc[lokal_nr].adr := adres;

          idx:=load_lab(ety, true);			// !!! TRUE
          t_loc[lokal_nr].idx := idx;


          save_end(__endl);

          zapisz_lokal;
          lokal_name:=lokal_name+ety+'.';

	  if lokal_name='.' then lokal_name:='';

	  end;

          ety:='';
         end;

(*----------------------------------------------------------------------------*)
(*  .ENDL                                                                     *)
(*----------------------------------------------------------------------------*)
   __endl:
        if ety<>'' then blad(zm,38) else
         if macro_rept_if_test then
          if lokal_nr>0 then begin

           save_lst(' ');

           if not(proc) then oddaj_var;

           oddaj_lokal(zm);

           if t_loc[lokal_nr].idx>=0 then begin
            t_lab[t_loc[lokal_nr].idx].lln:=adres-t_loc[lokal_nr].adr;
            t_lab[t_loc[lokal_nr].idx].lid:=true;
           end;

           org_ofset := t_loc[lokal_nr].ofs;

//           dec(end_idx);

           get_address_update;

          end else
           blad(zm,28);

(*----------------------------------------------------------------------------*)
(*  .REPT expression                                                          *)
(*----------------------------------------------------------------------------*)
   __rept:
        if if_test then
         if rept then blad(zm,43) else begin

          save_lab(ety,adres,bank,zm);
          save_lst(' ');

          if rept_cnt=0 then SetLength(t_rep, 1);

          rept:=true;

          get_rept(i, zm);

//          save_mac(zm);            // zapisanie pierwszego .REPT

          ety:='';
         end;


(*----------------------------------------------------------------------------*)
(*  .ENDR                                                                     *)
(*----------------------------------------------------------------------------*)
   __endr:
        if if_test then begin

        if not(rept) then blad(zm,51);

//          writeln(pass,',','stop'); halt;       // !!! to nie powinno wystapić
//          dirENDR(zm,a,old_str, 0);

          ety:='';
        end;


(*----------------------------------------------------------------------------*)
(*  label .STRUCT [label]                                                     *)
(*  wystapienie dyrektywy .STRUCT oznacza conajmniej trzy przebiegi asemblacji*)
(*----------------------------------------------------------------------------*)
   __struct:
        if macro_rept_if_test then
         if struct.use then blad(zm,56) else begin

           if ety='' then ety:=get_lab(i,zm, true);

           if pass=0 then reserved_word(ety,zm);

           omin_spacje(i,zm);
           if not(test_char(i,zm)) then blad(zm,4);

           label_type:='C';

           struct.drelocUSE := dreloc.use;
           struct.drelocSDX := dreloc.sdx;

           dreloc.use := false;
           dreloc.sdx := false;


           upd_structure(ety, zm);


           zapisz_lokal;
           lokal_name:=lokal_name+ety+'.';

           struct.use := true;

         // zapamietujemy adres, aby oddac go po .ENDS
           struct.adres := adres;

           save_lst('a');

           save_end(__ends);

           ety:='';
         end;


(*----------------------------------------------------------------------------*)
(*  .ENDS                                                                     *)
(*  zapisujemy w tablicy 'T_STR' dlugosc i liczbe pol struktury               *)
(*----------------------------------------------------------------------------*)
   __ends:
        if ety<>'' then blad(zm,38) else
         if macro_rept_if_test then
          if not(struct.use) then blad(zm,55) else begin

           save_lst(' ');

           oddaj_lokal(zm);

           struct.use := false;

           t_str[struct.idx].siz := adres - struct.adres; // zapisujemy dlugosc struktury

           t_str[struct.idx].ofs := struct.cnt;           // i liczbe pol struktury

           adres := struct.adres;                         // zwracamy stary adres asemblacji

           inc(struct.id);  // zwiekszamy identyfikator struktury (liczba struktur)

           struct.cnt := -1;

//           dec(end_idx);
           dec_end(zm, __ends);

           dreloc.use := struct.drelocUSE;
           dreloc.sdx := struct.drelocSDX;
          end;


(*----------------------------------------------------------------------------*)
(*  .ENUM                                                                     *)
(*----------------------------------------------------------------------------*)
   __enum:
        if macro_rept_if_test then
         if enum.use then blad(zm,122) else begin

           if ety='' then ety:=get_lab(i,zm, true);

           if pass=0 then reserved_word(ety,zm);

           omin_spacje(i,zm);
           if not(test_char(i,zm)) then blad(zm,4);

           label_type:='C';

           enum.drelocUSE := dreloc.use;
           enum.drelocSDX := dreloc.sdx;

           dreloc.use:=false;
           dreloc.sdx:=false;

           save_lab(ety, 0, __id_enum, zm);


           zapisz_lokal;
           lokal_name:=lokal_name+ety+'.';

           enum.use := true;
           enum.val := 0;
           enum.max := 0;

           save_lst('a');

           save_end(__ende);

           ety:='';
         end;


(*----------------------------------------------------------------------------*)
(*  .ENDE                                                                     *)
(*----------------------------------------------------------------------------*)
   __ende:
        if ety<>'' then blad(zm,38) else
         if macro_rept_if_test then
          if not(enum.use) then blad(zm,55) else begin

           txt:=lokal_name;
           SetLength(txt, length(txt)-1);
           idx:=load_lab(txt,false);

           t_lab[idx].adr:=ValueToType(enum.max);

           save_lst(' ');

           oddaj_lokal(zm);

           enum.use := false;

//           dec(end_idx);
           dec_end(zm,__ende);

           dreloc.use := enum.drelocUSE;
           dreloc.sdx := enum.drelocSDX;

          end;


(*----------------------------------------------------------------------------*)
(*  zapisujemy wartosc do tablicy .ARRAY                                      *)
(*----------------------------------------------------------------------------*)
   __array_run:
      if ety<>'' then blad(zm,38) else begin

        get_data_array(i,zm, array_idx-1);

      end;


(*----------------------------------------------------------------------------*)
(*  .ARRAY label [elements0] [elements1] [...] type = expression              *)
(*  tablica ze zdefiniowanymi wartosciami                                     *)
(*----------------------------------------------------------------------------*)
   __array:
        if aray then blad(zm,60) else
         if macro_rept_if_test then begin

          if ety='' then ety:=get_lab(i,zm, true);

          if pass=0 then reserved_word(ety,zm);

          get_array(i,zm, ety, adres);

          war:=0;       // dopuszczalna maksymalna wartosc typu D-WORD

          omin_spacje(i,zm);
          if zm[i]='=' then begin
            __inc(i,zm);
            war:=oblicz_wartosc_noSPC(zm,zm,i,#0,tType[ t_arr[array_idx-1].siz ]);
          end;

          omin_spacje(i,zm);
          if not(test_char(i,zm)) then blad(zm,4);

          for j:=0 to t_arr[array_idx-1].len-1 do t_tmp[j]:=cardinal(war);  // FILLCHAR wypelnia tylko bajtami

          aray := true;

          save_end(__enda);

          ety:='';
         end;


(*----------------------------------------------------------------------------*)
(*  .ENDA                                                                     *)
(*----------------------------------------------------------------------------*)
   __enda:
        if ety<>'' then blad(zm,38) else
         if macro_rept_if_test then
          if not(aray) then blad(zm,59) else begin

           aray := false;

           v := t_arr[array_idx-1].siz;


           if not t_arr[array_idx-1].def then begin     // nie okreslono rozmiaru tablicy

            _doo := array_used.max ;                    // rozmiar tablicy na podstawie ilosci danych

            t_arr[array_idx-1].elm[0].cnt := _doo;
            t_arr[array_idx-1].len        := _doo*v;

            if t_arr[array_idx-1].len-1>$FFFF then blad(zm,62);
           end;


           if struct.use then yes := false else
            if proc then yes := t_prc[proc_nr-1].use else yes := true;


           if yes then
            for idx:=0 to (t_arr[array_idx-1].len div v)-1 do save_dta(t_tmp[idx], zm, tType[v], 0);

           t:=''; save_lst(' ');

//           dec(end_idx);
           dec_end(zm,__enda);

          end;


(*----------------------------------------------------------------------------*)
(*  label EXT type                                                            *)
(*----------------------------------------------------------------------------*)
   __ext:
   if ety='' then blad(zm,15) else
    if macro_rept_if_test then
     if loop_used then blad(zm,36) else begin

      v := get_typeExt(i,zm);

      save_extLabel(i,ety,zm,v);

      nul.i:=0;
      save_lst('l');

      ety:='';
     end;


(*----------------------------------------------------------------------------*)
(*  .EXTRN label .PROC (par1, par2, ...) [.var]|[.reg]                        *)
(*  .EXTRN label1, label2, label3 ... type                                    *)
(*  rozbudowany odpowiednik pseudo rozkazu EXT                                *)
(*----------------------------------------------------------------------------*)
 __extrn:
    if macro_rept_if_test then begin
//     if loop_used then blad(zm,36) else begin

      nul.i:=0;
      save_lst('l');
      v:=0;

      if ety='' then begin         // jesli .EXTRN nie poprzedza etykieta

       while true do begin

        get_parameters(i,zm,par,false);
        v:=get_typeExt(i,zm);

        _doo:=High(par);
        if _doo=0 then blad(zm,15);

        for _odd:=_doo-1 downto 0 do begin
         txt:=par[_odd];

         if txt<>'' then
          save_extLabel(i,txt,zm,v)
         else
          blad(zm,15);

        end;

        omin_spacje(i,zm);
        if (v=__proc) or (test_char(i,zm)) then Break;
       end;

      end else begin               // jesli .EXTRN poprzedza etykieta
       v := get_typeExt(i,zm);
       save_extLabel(i,ety,zm,v);
      end;

    ety:='';
   end;


(*----------------------------------------------------------------------------*)
(*  .VAR label1, label2, label3 ... TYPE [=address]                           *)
(*  .VAR TYPE label1, label2 ....                                             *)
(*  .ZPVAR label1, label2, label3 ... TYPE [=address]                         *)
(*  .ZPVAR TYPE label1, label2 ....                                           *)
(*----------------------------------------------------------------------------*)
 __var, __zpvar:
 if ety<>'' then blad(zm,38) else
  if (pass>0) and macro_rept_if_test then
//   if (adres<0) and (mne.l=__var) then blad(zm,10) else
    if rept_run then blad(zm,36) else begin

//     nul.i:=0;
     save_lst('a');

     omin_spacje(i,zm);

  if (mne.l=__zpvar) and (zm[i]='=') then begin          // .ZPVAR = XX
   inc(i);
   zpvar:=integer( oblicz_wartosc_noSPC(zm,zm,i,#0,'A') );

   subrange_bounds(zm,zpvar,$FF);
  end else begin

     if pass_end<3 then pass_end:=3;    // !!! potrzebne conajmniej 3 przebiegi !!!

     while true do begin
      get_vars(i,zm,par, mne.l);

      omin_spacje(i,zm);
      if test_char(i,zm,#0,'=') then Break;
     end;

     txt:=zm;

   // sprawdz czy zostal okreslony adres umiejscowienia zmiennych '= ADDRESS'
     idx:=-1;

     if par[high(par)-1]<>'' then
      if par[high(par)-1][1]='=' then begin
       i:=1;
       txt:=par[high(par)-1];
      end;


     if txt<>'' then
      if txt[i]='=' then begin                // nowy adres alokacji
       inc(i);
       idx:=integer( oblicz_wartosc_noSPC(txt,zm,i,#0,'A') );

       testRange(zm,idx,87);
      end;


     if mne.l=__zpvar then begin

      if idx>=0 then zpvar:=idx;

       for _doo:=0 to var_idx-1 do
        if t_var[_doo].id=var_id then begin

         t_var[_doo].adr:=zpvar;
         t_var[_doo].zpv:=true;

         if zpvar+t_var[_doo].cnt*t_var[_doo].siz>256 then
          blad(zm,0)
         else
          for k:=0 to t_var[_doo].cnt*t_var[_doo].siz-1 do begin

           if (pass=pass_end) and t_zpv[zpvar] then warning(109);

           t_zpv[zpvar]:=true;

           inc(zpvar);
          end;

        end;

     end else begin

      if idx>=0 then
       for _doo:=0 to var_idx-1 do
        if t_var[_doo].id=var_id then begin
         t_var[_doo].adr:=idx;
         t_var[_doo].zpv:=false;
         inc(idx, t_var[_doo].cnt*t_var[_doo].siz);
        end;

     end;

     inc(var_id);

  end;

     ety:='';
    end;


// !!! wymaga dodania obslugi dla SDX, obecnie brak obslugi relokacji !!!
(*----------------------------------------------------------------------------*)
(*  .BY [+byte] bytes and/or ASCII                                            *)
(*  .CB [+byte] bytes and/or ASCII                                            *)
(*  .SB [+byte] bytes and/or ASCII                                            *)
(*  .WO words                                                                 *)
(*  .HE hex bytes                                                             *)
(*  .DBYTE                                                                    *)
(*----------------------------------------------------------------------------*)
 __by, __wo, __he, __sb, __cb, __dbyte:
  if {dreloc.use or dreloc.sdx or} struct.use then begin

   if struct.use then
    blad(zm,58);
   //else
   // blad(zm,71);

  end else
   if macro_rept_if_test then begin

    save_lab(ety,adres,bank,zm);

    case mne.l of
        __cb: get_maeData(zm,i, 'C');
        __by: get_maeData(zm,i, 'B');
        __wo: get_maeData(zm,i, 'W');
        __he: get_maeData(zm,i, 'H');
        __sb: get_maeData(zm,i, 'S');
     __dbyte: get_maeData(zm,i, 'D');
    end;

    ety:='';
   end;


(*----------------------------------------------------------------------------*)
(*  .WHILE .TYPE ARG1 OPERAND ARG2 [.AND|.OR .TYPE ARG3 OPERAND ARG4]         *)
(*----------------------------------------------------------------------------*)
 __while:
    if macro_rept_if_test then begin
//     if loop_used then blad(zm,36) else begin

//      if ety='' then ety:=get_lab(i,zm, true);

      save_lab(ety,adres,bank,zm);
      save_lst('a');

      if while_name='' then while_name:=lokal_name;
      while_name:=while_name+IntToStr(while_nr)+'.';   // sciezka dostepu do WHILE

      r:=0;
      long_test:='';
      wyrazenie_warunkowe(i, long_test, zm,txt,tmp,v,r, '\EX LDA#0\:?J/2-1 ORA#0\.ENDL');

//      if long_test<>'' then begin
//       create_long_test(v, r, long_test, txt, tmp);
//       long_test:=long_test+'\EX LDA#0\:?J/2-1 ORA#0\.ENDL';
//      end;


      save_end(__endw);


      ety:=__while_label+while_name;        // poczatek .WHILE

      save_fake_label(ety,zm,adres);


      ety:=__endw_label+while_name;         // koniec WHILE

      if long_test='' then
       mne := asm_test(txt,tmp,zm, ety, r,v)
      else begin

       idx:=High(t_mac);  _odd:=idx+1;

       t_mac[idx]:=long_test+'\ JEQ '+ety;

       line_add:=line-1;

       save_lst('i');
       txt:=zm;
       zapisz_lst(txt);

       opt_tmp:=opt;
       opt:=opt and byte(not(opt_L));

       code6502:=true;


       analizuj_mem(idx,_odd, zm,a,old_str, 0,1, false);


       code6502:=false;

       line_add:=0;

       opt:=opt_tmp;

       bez_lst:=true;
      end;


      inc(whi_idx);

      inc(while_nr);

      ety:='';
    end;


(*----------------------------------------------------------------------------*)
(*  .ENDW                                                                     *)
(*----------------------------------------------------------------------------*)
 __endw:
    if ety<>'' then blad(zm,38) else
     if macro_rept_if_test then
      if whi_idx>0 then begin
//     if loop_used then blad(zm,36) else begin

        save_lst('a');

        dec(whi_idx);


     ety:=__while_label+while_name;

     war:=load_lab(ety,false);    // odczytujemy wartosc etykiety poczatku petli WHILE ##B
     if war>=0 then begin
      tst:=t_lab[war].adr;

      save_relAddress(integer(war), reloc_value);

      if pass=pass_end then
       if t_lab[war].bnk<>bank then warning(70); // petla .WHILE musi znajdowac sie w obszarze tego samego banku
     end else
      tst:=0;


        txt:='JMP '+IntToStr(tst);
        k:=1;  mne:=oblicz_mnemonik(k,txt,zm);


     ety:=__endw_label+while_name;

     idx := adres + 3;            // E## = aktualny adres + 3 bajty (JMP)

     save_fake_label(ety,zm,idx);


        obetnij_kropke(while_name);

//        dec(end_idx);
        dec_end(zm,__endw);

        ety:='';
       end else blad(zm,88);


(*----------------------------------------------------------------------------*)
(*  .TEST .TYPE ARG1 OPERAND ARG2 [.AND|.OR .TYPE ARG3 OPERAND ARG4]          *)
(*----------------------------------------------------------------------------*)
 __test:
    if macro_rept_if_test then begin

      save_lab(ety,adres,bank,zm);
      save_lst('a');

      if test_name='' then test_name:=lokal_name;
      test_name:=test_name+IntToStr(test_nr)+'.';   // sciezka dostepu do TEST

      long_test:='';
      wyrazenie_warunkowe(i, long_test,zm,txt,tmp,v,r, '\EX LDA#0\:?J/2-1 ORA#0\.ENDL');

//      if long_test<>'' then begin
//       create_long_test(v, r, long_test, txt, tmp);
//       long_test:=long_test+'\EX LDA#0\:?J/2-1 ORA#0\.ENDL';
//      end;


      save_end(__endt);


      ety:=__test_label+test_name;          // poczatek #IF __TEST_LABEL

      save_fake_label(ety,zm,adres);


      ety:=__telse_label+test_name;        // sprawdzamy czy wystapilo #ELSE
      if load_lab(ety,false)<0 then
       ety:=__endt_label+test_name;        // jesli nie bylo #ELSE to skok do #END


      if long_test='' then
       mne := asm_test(txt,tmp,zm, ety, r,v)
      else begin

       idx:=High(t_mac);  _odd:=idx+1;

       t_mac[idx]:=long_test+'\ JEQ '+ety;

       line_add:=line-1;

       save_lst('i');
       txt:=zm;
       zapisz_lst(txt);

       opt_tmp:=opt;
       opt:=opt and byte(not(opt_L));


       code6502:=true;

       analizuj_mem(idx,_odd, zm,a,old_str, 0,1, false);

       code6502:=false;


       line_add:=0;

       opt:=opt_tmp;

       bez_lst:=true;
      end;


      t_els[test_idx]:=false;

      inc(test_idx);

      if test_idx>High(t_els) then SetLength(t_els, test_idx+1);


      inc(test_nr);

      ety:='';
    end;


(*----------------------------------------------------------------------------*)
(*  .TELSE                                                                    *)
(*----------------------------------------------------------------------------*)
 __telse:
    if ety<>'' then blad(zm,38) else
     if macro_rept_if_test then
      if test_idx>0 then begin

        if t_els[test_idx-1] then blad(zm,95);

        txt:='JMP '+__endt_label+test_name;
        mne:=asm_mnemo(txt, zm);

        t_els[test_idx-1]:=true;

        ety:=__telse_label+test_name;          // adres #ELSE __TELSE_LABEL
        save_fake_label(ety,zm,adres);


        dec(adres, mne.l);


        ety:='';
      end else blad(zm,95);


(*----------------------------------------------------------------------------*)
(*  .ENDT                                                                     *)
(*----------------------------------------------------------------------------*)
 __endt:
    if ety<>'' then blad(zm,38) else
     if macro_rept_if_test then
      if test_idx>0 then begin
//     if loop_used then blad(zm,36) else begin

        save_lst('a');

        dec(test_idx);


     ety:=__test_label+test_name;

     war:=load_lab(ety,false);              // adres #IF __TEST_LABEL
     if war>=0 then
      if pass=pass_end then
       if t_lab[war].bnk<>bank then warning(70); // TEST musi znajdowac sie w obszarze tego samego banku


     ety:=__endt_label+test_name;           // adres #END dla bloku #IF __ENDT_LABEL
     save_fake_label(ety,zm,adres);


        obetnij_kropke(test_name);

//        dec(end_idx);
        dec_end(zm,__endt);

        ety:='';
       end else blad(zm,95);


(*----------------------------------------------------------------------------*)
(*  .DEF label                                                                *)
(*----------------------------------------------------------------------------*)
 __def:
    if ety<>'' then blad(zm,38) else
     if macro_rept_if_test then begin

      idx:=adres;

      omin_spacje(i,zm);

      label_type:='V';


      if zm[i]=':' then begin
       old_case:=true;           // zostal uzyty znak ':' w nazwie etykiety
       inc(i);
      end else
       old_case:=false;          // znak ':' nie zostal uzyty w nazwie etykiety

      ety:=get_lab(i,zm,true);

      omin_spacje(i,zm);

      txt:=zm;                   // podstawiamy ZM pod TXT

      if txt[i] in ['+','-'] then
       if txt[i+1] in ['+','-','='] then operator_zlozony(i,txt,ety, old_case);


      if txt[i]='=' then begin
       __inc(i,txt);

       variable:=false;

       idx:=oblicz_wartosc_noSPC(txt,zm,i,#0,'W');

       if not(variable) then label_type:='C';

      end else
       if not(test_char(i,txt)) then blad(zm,58);


      nul.i:=idx;
      save_lst('l');
      data_out := true;     // wymus pokazanie w pliku LST podczas wykonywania makra
                            // !!! jesli wystapila dyrektywa .IFNDEF to nie pokaze !!!

      old_run_macro := run_macro;
      run_macro     := false;

//      old_loopused  := dreloc.use;
//      dreloc.use    := false;

      mne_used      := true;


      if old_case then
       s_lab(ety,idx,bank,zm,ety[1])   // etykieta globalna
      else
       save_lab(ety,idx,bank,zm);      // etykieta w aktualnym zasiegu


      run_macro     := old_run_macro;

//      dreloc.use    := old_loopused;

      ety:='';
     end;


(*----------------------------------------------------------------------------*)
(*  .USING label [,label2...]                                                 *)
(*----------------------------------------------------------------------------*)
 __using:
    if ety<>'' then blad(zm,38) else
     if macro_rept_if_test then begin

      save_lst('i');

      get_parameters(i,zm,par,false);

      if pass>0 then
       for k:=High(par)-1 downto 0 do begin

        txt:=par[k];

        _odd:=load_lab(txt, false);
        if _odd<0 then blad_und(zm,txt,5);

        t_usi[usi_idx].lok:=end_idx;
        t_usi[usi_idx].lab:=txt;

        if proc then
         t_usi[usi_idx].nam:=proc_name
        else
         t_usi[usi_idx].nam:=lokal_name;

        inc(usi_idx);

        SetLength(t_usi, usi_idx+1);
       end;

     end;


(*----------------------------------------------------------------------------*)
(*  .CBM 'text'								      *)
(*----------------------------------------------------------------------------*)
 __cbm:
    if macro_rept_if_test then begin

     save_lab(ety,adres,bank,zm);

     save_lst('a');

     txt:=get_string(i,zm,zm,true);

     for j:=1 to length(txt) do
      case txt[j] of
       'a'..'z': save_dst( byte(txt[j]) - 96 );
       '['..'_': save_dst( byte(txt[j]) - 64 );
            '`': save_dst(64);
	    '@': save_dst(0);
      else
       save_dst( byte(txt[j]) )
      end;

     inc(adres, length(txt));

     ety:='';
    end;


(*----------------------------------------------------------------------------*)
(*  .BI binary								      *)
(*----------------------------------------------------------------------------*)
 __bi:
    if macro_rept_if_test then begin

     save_lab(ety,adres,bank,zm);

     save_lst('a');

     omin_spacje(i,zm);

     if test_char(i,zm) then blad(zm,23);

     k:=0;
     v:=0;

     while not(test_char(i,zm)) do begin
       txt:=get_dat(i,zm,',',true);

       if txt = '' then blad(zm, 0);


       if txt[length(txt)] = '*' then begin

         for j:=1 to length(txt)-1 do begin

          case txt[j] of
	   '0': begin v:=v or tora[k]; inc(k) end;
  	   '1': inc(k);
	  else
	    blad(zm, 0)
	  end;

	  if k = 8 then begin save_dst(v); v:=0; k:=0 end;

         end;

       end else

         for j:=1 to length(txt) do begin

          case txt[j] of
  	   '0': inc(k);
	   '1': begin v:=v or tora[k]; inc(k) end;
	  else
	    blad(zm, 0)
	  end;

	  if k = 8 then begin save_dst(v); v:=0; k:=0 end;

         end;

       if zm[i] in [',',' ',#9] then __next(i,zm) else Break;
     end;

     if k <> 0 then save_dst(v);

     ety:='';
    end;



(*----------------------------------------------------------------------------*)
(*  .FL									      *)
(*----------------------------------------------------------------------------*)
 __fl:
    if macro_rept_if_test then begin

     save_lab(ety,adres,bank,zm);

     save_lst('a');

     omin_spacje(i,zm);

     if test_char(i,zm) then blad(zm,23);

     while not(test_char(i,zm)) do begin
       txt:=get_dat(i,zm,',',true);
       save_fl(txt, zm);
       if zm[i] in [',',' ',#9] then __next(i,zm) else Break;
     end;

     ety:='';
    end;


(*----------------------------------------------------------------------------*)
(*  label EQU [=] expression                                                  *)
(*  label SMB string[8]                                                       *)
(*  label SET expression                                                      *)
(*----------------------------------------------------------------------------*)
   __equ,__smb,__set,__addEqu,__addSet:
       if ety='' then blad(zm,15) else
        if macro_rept_if_test then
         if loop_used then blad(zm,36) else begin

           if dreloc.use then
            if mne.l in [__equ,__smb] then blad(zm,71);

           label_type:='C';

           old_case      := dreloc.use;   // deklaracje etykiet w bloku .RELOC nie moga byc relokowalne
           dreloc.use    := false;


           if mne.l=__smb then begin   // SMB

            txt:=get_smb(i,zm);

	    // jesli za nazwa symbolu lezy znak ^ wtedy markujemy Weak Symbol
	    if zm[i] = '^' then begin
             t_smb[smb_idx].weak := true;
	     inc(i);
	    end;

          // wymuszamy relokowalnosc dla tej etykiety
          // jesli BLOK>1 to zaznaczy jako etykiete relokowalna
            k:=blok; blok:=$FFFF;
            save_lab(ety,smb_idx,__id_smb,zm);
            blok:=k;


          // zapisujemy etykiete symbolu SMB w tablicy T_SMB
            t_smb[smb_idx].smb:=txt;                                 // SAVE_SMB
            inc(smb_idx);                                            //
            if smb_idx>High(t_smb) then SetLength(t_smb,smb_idx+1);  //


            war:=__rel;

           end else begin              // EQU, addEQU

            branch:=true;              // dla EQU i addEQU nie ma relokowalnosci

           // nie mozna przypisac wartosci etykiety EXTERNAL, SMB (BLOCKED = TRUE)
            blocked := true;

           // sprawdzamy czy deklaracja etykiety powiodla sie (UNDECLARED = FALSE)
           // procedura OBLICZ_WARTOSC zmodyfikuje UNDECLARED na TRUE jesli wystapi
           // proba odwolania do niezdefiniowanej etykiety

            undeclared:=false;


            variable:=false;


            etyArray:=ety;

            war:=oblicz_wartosc_noSPC(zm,zm,i,#0,'F');


            if variable then label_type:='V';


            blocked := false;          // !!! koniecznie przywracamy BLOCKED = FALSE !!!

            mne_used:=true;            // konieczny test dla zmieniajacych sie wartosci etykiet


            _odd:=load_lab(ety, true); // !!! TRUE


            if etyArray='' then                          // była deklaracja przez .ARRAY

             t_arr[array_idx-1].adr := war               // auaktualniamy adres .ARRAY

            else
             if (mne.l in [__set, __addSet]) and (_odd>=0) and (pass>0) then begin
             //s_lab(ety,cardinal(war),bank,zm,'?')      // !!! nie zadziala dla blokow .LOCAL itp. !!!

              t_lab[_odd].adr := war;                    // !!! tylko w ten sposob i "(_ODD>=0) AND (PASS>0)" !!!
              t_lab[_odd].pas := pass;
             end else
              save_lab(ety,cardinal(war),bank,zm);


            _odd:=load_lab(ety, true); // !!! TRUE

            if _odd>=0 then t_lab[_odd].sts := undeclared;

            undeclared:=false;         // !!! koniecznie przywracamy UNDECLARED = FALSE !!!

            data_out := true;          // wymus pokazanie w pliku LST podczas wykonywania makra

            mne_used := false;

           end;


           nul.i:=integer( war );
           save_lst('l');


           if mne.l=__addEqu then begin
            zapisz_lst(tmpZM);
            zm:='';
           end;


           dreloc.use := old_case;

           ety:='';
          end;


(*----------------------------------------------------------------------------*)
(*  OPT holscmtb?f +-                                                         *)
(*----------------------------------------------------------------------------*)
(*  bit                                                                       *)
(*   0 - Header                        default = yes   'h+'                   *)
(*   1 - Object file                   default = yes   'o+                    *)
(*   2 - Listing                       default = no    'l-'                   *)
(*   3 - Screen (listing on screen)    default = no    's-'                   *)
(*   4 - CPU 8bit/16bit                default = 6502  'c-'                   *)
(*   5 - visible macro                 default = no    'm-'                   *)
(*   6 - track sep rep                 default = no    't-'                   *)
(*   7 - banked mode                   default = no    'b-'                   *)
(*----------------------------------------------------------------------------*)
   __opt:
       if macro_rept_if_test then begin

         txt:=get_dat_noSPC(i,zm,zm,',');   // pomijamy spacje

         j:=1;

         while j<=length(txt) do begin

          ch:=txt[j+1];

          opt_tmp:=opt;

          v:=0;

          case UpCase(txt[j]) of
           'B': v:=opt_B;
           'C': v:=opt_C;
           'F': raw.use := (ch='+');
           'H': v:=opt_H;
           'L': v:=opt_L;
           'M': v:=opt_M;
           'O': v:=opt_O;
           'R': regAXY_opty := (ch='+');
           'S': v:=opt_S;
           'T': v:=opt_T;
           '?': mae_labels := (ch='+');
          else
           blad(zm,16);
          end;

          case ch of
           '+': opt:=opt or v;
           '-': opt:=opt and byte(not(v));
          else
           blad(zm,16);
          end;

          if (opt_tmp and opt_H)<>(opt and opt_H) then   // OPT H-
           if (opt and opt_H)=0 then save_hea;

          inc(j,2);
         end;

         data_out:=true;

         save_lst(' ');
       end;


(*----------------------------------------------------------------------------*)
(*  ORG adres [,adres2]                                                       *)
(*  RUN adres                                                                 *)
(*  INI adres                                                                 *)
(*  BLK                                                                       *)
(*----------------------------------------------------------------------------*)
   __org, __run, __ini, __blkSpa, __blkRel, __blkEmp:
    if if_test then
     if loop_used or rept then blad(zm,36) else
      if dreloc.use then blad(zm,71) else
       if first_org and (ety<>'') then blad(zm,10) else begin


         if (org_ofset>0) and ((lokal_name<>'') or proc) then blad(zm,71);


         if hea_ofs.adr >= 0 then
          raw.old := hea_ofs.adr+(adres-hea_ofs.old)
         else
          raw.old := adres;


         label_type:='V';

         data_out:=true;

         save_lst('a');

         branch:=true;    // relokowalnosc tutaj niemozliwa

         rel_ofs:=0; {org_ofs:=0;}
         idx:=-$FFFF;  hea_ofs.adr:=-1;  _odd:=-1;

         save_lab(ety,cardinal(adres),bank,zm);

         omin_spacje(i,zm);

         r := mne.l;    // !!! koniecznie V := MNE.L !!! aby zadzialalo RUN, INI
                        // !!! RUN, INI modyfikuja MNE.L !!!

         case r of

         // BLK SPARTA a
          __blkSpa:
               begin
                dreloc.sdx:=true;

                blok:=0;

                opt_tmp:=opt;
                opt_h_minus;

              // a($fffa),a(str_adr),a(end_adr)
                save_dstW( $fffa );

                idx:=integer( oblicz_wartosc_noSPC(zm,zm,i,',','A') );

                opt:=opt_tmp;
               end;


         //BLK R[eloc] M[ain]|E[xtended]
          __blkRel:
              begin
                dreloc.sdx:=true;

                if ds_empty>0 then begin
                 oddaj_ds;

                 bez_lst:=false;
                 save_lst('a');
                end;

                ds_empty:=0;

                opt_tmp:=opt;
                opt_h_minus;

                v := getMemType(i,zm);

                add_blok(zm);

              // a($fffe),b(blk_num),b(blk_id)
              // a(blk_off),a(blk_len)
                save_dstW( $fffe );
                save_dst(byte(blok));
                save_dst(memType);

                if blok=1 then
                 idx:=__rel
                else begin
                 rel_ofs:=adres-__rel;
                 _odd:=adres; idx:=adres;
                end;

                opt:=opt_tmp;
              end;


         //BLK E[mpty] expression M[ain]|E[xtended]
          __blkEmp:
              begin

                _odd:=integer( oblicz_wartosc_noSPC(zm,zm,i,' ','A') );  // !!! koniecznie znak spacji ' ' !!!
                                                                     // blk empty empend-tdbuf extended
                v := getMemType(i,zm);

                if _odd>0 then begin

                  opt_tmp := opt;
                  opt_h_minus;

                  blk_empty(_odd, zm);

                  opt := opt_tmp;

                  if ds_empty>0 then blad(zm,57);  // albo .DS albo BLK EMPTY, nie mozna obu naraz

                end;

                idx:=adres + _odd;

              end;


          // ORG
          __org: begin

                if dreloc.sdx then blad(zm,71);

                if not(NoAllocVar) and not(proc) and (lokal_nr=0) then oddaj_var;


                if opt and opt_C>0 then          // dla 65816 dopuszczamy adres 24 bit
                 typ:='T'
                else
                 typ:='A';


                NoAllocVar:=false;

                org_ofset:=0;

                if (zm[i+1]=':') and (UpCase(zm[i])='R') then begin         // org r:  (XASM)
                 inc(i, 2);

                 idx:=integer( oblicz_wartosc_noSPC(zm,zm,i,#0,typ) );

                 hea_ofs.adr := adres;
                 hea_ofs.old := idx;
                 org_ofset := idx - hea_ofs.adr;

                end else

                if zm[i]='[' then begin
                 opt_tmp := opt;
                 opt_h_minus;

                 txt:=ciag_ograniczony(i,zm,true);
                 k:=1;
                 if pass>1 then oblicz_dane(k,txt,zm,1);

                 omin_spacje(i,zm);
                 if zm[i]=',' then begin
                  __inc(i,zm);
                  idx:=integer( oblicz_wartosc_noSPC(zm,zm,i,',',typ) );
                 end;

                 opt := opt_tmp;

                end else
                 idx:=integer( oblicz_wartosc_noSPC(zm,zm,i,',',typ) );

                omin_spacje(i,zm);
                if (i<=length(zm)) and (zm[i]=',') then begin
                 __inc(i,zm);

                 hea_ofs.adr := integer( oblicz_wartosc_noSPC(zm,zm,i,#0,typ) );
                 if hea_ofs.adr < 0 then blad(zm,10);

                 hea_ofs.old := idx;
                 org_ofset := idx - hea_ofs.adr;

                end;


                if not(first_org) then           // koniecznie IF NOT(FIRST_ORG) inaczej nic nie zapisze
                 if (adres <> idx) and raw.use then begin

                  if raw.old < 0 then
                   k:=0
                  else
                   if hea_ofs.adr >= 0 then
                    k:=hea_ofs.adr-raw.old
                   else
                    k:=idx-raw.old;


                  if k < 0 then begin

		    if pass > 0 then blad(zm,108, hex(idx,4));

		  end else
                   if not(hea) then inc(fill,k);  // IF NOT(HEA) czeka az zacznie zapisywac cos do pliku


                  adres:=idx;

                 end;

               end;


          // RUN,INI
          __run,__ini:
               begin

                if dreloc.sdx then blad(zm,71);        // Illegal instruction at RELOC block
                if opt and opt_H=0 then blad(zm,111);  // Illegal when Atari file headers disabled

                oddaj_var;

                idx:=integer( oblicz_wartosc_noSPC(zm,zm,i,#0,'A') );
                mne.l:=2;

                mne.h[0]:=byte(idx);
                mne.h[1]:=byte(idx shr 8);

                idx:=$2e0 + r - __run;

                runini.adr := adres;
                runini.use := true;
               end;
         end;


         if (adres<>idx) or (_odd>=0) then begin

           save_hea;

           adres:=idx;

           if r<>__blkEmp then org:=true;	// R = MNE.L
         end;


         if ( (opt and opt_C>0) and (idx>=0) and (idx<=$FFFFFF) ) or ( (idx>=0) and (idx<=$FFFF) ) then
          first_org:=false
         else
          blad(zm,0,'('+IntToStr(idx)+' must be between 0 and 65535)');		// !!! koniecznie blad(zm,0) !!! w celu akceptacji
										// ORG-ów < 0 w poczatkowych przebiegach asemblacji

         if raw.use and (r in [__run, __ini]) then first_org:=true;

         ety:='';
        end;


(*----------------------------------------------------------------------------*)
(*  .PUT [index] = VALUE,...                                                  *)
(*----------------------------------------------------------------------------*)
   __put:
     if macro_rept_if_test then begin

       save_lab(ety,adres,bank,zm);

       omin_spacje(i,zm);

       array_used.max:=0;

       put_used:=true;

       blocked := true;
       get_data_array(i,zm, 0);   // predefiniowana tablica dla .PUT
       blocked := false;

       put_used:=false;

       ety:='';
      end;


(*----------------------------------------------------------------------------*)
(*  .SAV [index] ['file',length] | ['file',ofset,length]                      *)
(*----------------------------------------------------------------------------*)
   __sav:
//    if ety<>'' then blad(zm,38) else
     if macro_rept_if_test then begin

       save_lab(ety,adres,bank,zm);

       save_lst('a');

       idx_get:=0;

       omin_spacje(i,zm);

       if zm[i] in AllowStringBrackets then begin
        txt:=ciag_ograniczony(i,zm,true);
        k:=1; idx_get:=integer( oblicz_wartosc_noSPC(txt,zm,k,#0,'A') );
       end;

       txt:=get_string(i,zm,zm,false);

       omin_spacje(i,zm);

       if txt<>'' then
        if zm[i]=',' then
         __inc(i,zm)
        else
         blad(zm,23);

       _doo:=integer( oblicz_wartosc_noSPC(zm,zm,i,',','A') );

       omin_spacje(i,zm);

       if zm[i]=',' then begin
        __inc(i,zm);
        inc(idx_get, _doo);
        _doo:=integer( oblicz_wartosc_noSPC(zm,zm,i,',','A') );
       end;

       _odd:=idx_get+_doo;  if _odd>0 then dec(_odd);

       testRange(zm, _odd, 62); //subrange_bounds(zm,idx_get+_doo,$FFFF);

       test_eol(i,zm,zm,#0);

       if txt<>'' then begin
         txt:=GetFile(txt,zm);

         if pass=pass_end then begin
           WriteAccessFile(txt);

           AssignFile(g, txt); FileMode:=1; Rewrite(g,1);
           blockwrite(g, t_get[idx_get], _doo);
           closefile(g);
         end;

       end else begin

         if (pass=pass_end) and (_doo>0) then
          for idx:=0 to _doo-1 do save_dst(t_get[idx_get+idx]);

         inc(adres,_doo);
       end;

       ety:='';
      end;


(*----------------------------------------------------------------------------*)
(*  .PAGES                                                                    *)
(*----------------------------------------------------------------------------*)
   __pages:
    if ety<>'' then blad(zm,38) else
     if macro_rept_if_test then
      if adres<0 then blad(zm,10) else begin

       save_lst('a');

       war:=1;
       txt:=get_dat_noSPC(i,zm,zm,' ');

       if txt<>'' then begin
        k:=1; war:=oblicz_wartosc_noSPC(txt,zm,k,#0,'A');   // dopuszczalny zakres wartosci to .WORD

        k:=integer(war);
        testRange(zm, k, 0);
       end;

       omin_spacje(i,zm);
       if not(test_char(i,zm)) then blad(zm,4);

       t_pag[pag_idx].adr:= integer(adres and $7FFFFF00);
       t_pag[pag_idx].cnt:= integer(war) shl 8;

       inc(pag_idx);
       if pag_idx>High(t_pag) then SetLength(t_pag,pag_idx+1);

       save_end(__endpg);

//       ety:='';
      end;


(*----------------------------------------------------------------------------*)
(*  .ENDPG                                                                    *)
(*----------------------------------------------------------------------------*)
   __endpg:
    if ety<>'' then blad(zm,38) else
     if macro_rept_if_test then
      if pag_idx=0 then blad(zm,64) else begin

       save_lst('a');

       dec(pag_idx);

       _odd := t_pag[pag_idx].adr;
       _doo := (adres-1) and $7FFFFF00;

       if pass=pass_end then
        if (_doo-_odd) >= t_pag[pag_idx].cnt then warning(70);

//       dec(end_idx);
       dec_end(zm,__endpg);

//       ety:='';
      end;


(*----------------------------------------------------------------------------*)
(*  .RELOC                                                                    *)
(*----------------------------------------------------------------------------*)
   __reloc:
    if ety<>'' then blad(zm,38) else
     if macro_rept_if_test then
      if not(hea and not(mne_used)) then blad(zm,83) else begin

       inc(bank);
       if bank>=__id_param then blad(zm,45);

       test_wyjscia(zm,false);

       save_hea;

       if dreloc.use then begin
        rel_idx:=0; ext_idx:=0; extn_idx:=0;
        pub_idx:=0; smb_idx:=0; sym_idx:=0; skip_idx:=0;
        ext_used.use:=false; rel_used:=false; blocked:=false;
        blkupd.adr:=false; blkupd.ext:=false; blkupd.pub:=false;
        blkupd.sym:=false; blkupd.new:=false;
       end;

       save_lst(' ');

       k:=get_type(i,zm,zm,false);

       if k=1 then
        rel_ofs := __rel            // $0000
       else
        rel_ofs := __relASM;        // $0100


       omin_spacje(i,zm);
       tmp:=get_dat_noSPC(i,zm,zm, #0);
       if tmp<>'' then
        war:=oblicz_wartosc(tmp, zm)
       else
        war:=0;
       wartosc(zm, war, 'B');

       dreloc.use:=true;
       adres:=rel_ofs;

       first_org:=false;
       org:=true;

       save_dstW( __relHea );              // dodatkowy naglowek bloku relokowalnego 'MR'

       save_dst( byte(war) );              // kod bloku .RELOC użytkownika
       save_dst( byte(rel_ofs shr 8) );    // informacja o rodzaju bloku .BYTE (0) , .WORD (1)

     // zapisujemy wartosci etykiet dla stosu programowego
       indeks:=adr_label(__STACK_POINTER, false);  save_dstW( indeks );  // @stack_pointer
       indeks:=adr_label(__STACK_ADDRESS, false);  save_dstW( indeks );  // @stack_address
       indeks:=adr_label(__PROC_VARS_ADR, false);  save_dstW( indeks );  // @proc_vars_adr

      end;


(*----------------------------------------------------------------------------*)
(*  .LINK 'filename'                                                          *)
(*  pozwala dolaczyc kod relokowalny tzn. pliki DOS o adresie $0000           *)
(*----------------------------------------------------------------------------*)
   __link:
//    if ety<>'' then blad(zm,38) else
     if macro_rept_if_test then
      if dreloc.use then blad(zm,57) else begin

       save_lab(ety,adres,bank,zm);

//       save_lst(zm,'a');

//       omin_spacje(i,zm);
       txt:=get_string(i,zm,zm,true);

       txt:=GetFile(txt,zm);   if not(TestFile(txt)) then blad(txt,18);
       test_eol(i,zm,zm,#0);

       AssignFile(g, txt); FileMode:=0; Reset(g,1);

     // sprawdzamy czy wczytujemy plik DOS'a (pierwsze dwa bajty pliku = __HEA_DOS)
       t_lnk[0]:=0;
       t_lnk[1]:=0;

       blockread(g,t_lnk,2);
       if (t_lnk[0]+t_lnk[1] shl 8)<>__hea_dos then blad(zm,74);

       Reset(g,1);
       blockread(g,t_lnk,sizeof(t_lnk),IDX); // wczytujemy caly plik do T_LNK o dlugosci IDX

// w glownej petli uzywamy zmiennych IDX, K, _ODD

 _odd:=0; dlink.use:=false; dlink.len:=0; dlink.emp:=0;

 while _odd<idx do begin

        j:=fgetW(_odd);
        if j=$FFFF then j:=fgetW(_odd);


        case j of

 // blk RELOC
 __hea_reloc:
   begin

       if dlink.use then flush_link;

       k:=fgetW(_odd);              // odczytujemy dlugosc pliku relokowalnego, maks $FFFE

       if k=$ffff then              // tzn ze dlugosc pliku = 0
        k:=0
       else
        inc(k);                     // zwiekszamy o 1

       j:=fgetW(_odd);              // odczytujemy 2 bajty z dodatkowego naglowka 'MR'
       if j<>__relHea then blad(zm,74);
(*----------------------------------------------------------------------------*)
(* bajt 0 - nieuzywany                                                        *)
(* bajt 1 - bit 0     kod strony zerowej (0), kod poza strona zerowa (1)      *)
(*          bit 1..7  nieuzywne                                               *)
(*----------------------------------------------------------------------------*)
       fgetB(_odd);                 // odczytujemy 2 bajty z informacja o pliku .RELOC
       v:=fgetB(_odd);

       if (v=0) and (adres>$FF) then blad(zm,76);

       __link_stack_pointer_old := fgetW(_odd);       // @stack_pointer
       __link_stack_address_old := fgetW(_odd);       // @stack_address
       __link_proc_vars_adr_old := fgetW(_odd);       // @proc_vars_adr

       if pass=0 then begin

        if dlink.stc then
         if (__link_stack_pointer_old<>__link_stack_pointer) or
            (__link_stack_address_old<>__link_stack_address) or
            (__link_proc_vars_adr_old<>__link_proc_vars_adr) then warning(75);

        if not(dlink.stc) then begin
         __link_stack_pointer := __link_stack_pointer_old;
         __link_stack_address := __link_stack_address_old;
         __link_proc_vars_adr := __link_proc_vars_adr_old;

         txt:=mads_stack[ord(__STACK_POINTER)].nam; save_fake_label(txt,zm,__link_stack_pointer); //@stack_pointer
         txt:=mads_stack[ord(__STACK_ADDRESS)].nam; save_fake_label(txt,zm,__link_stack_address); //@stack_address
         txt:=mads_stack[ord(__PROC_VARS_ADR)].nam; save_fake_label(txt,zm,__link_proc_vars_adr); //@proc_vars_adr
        end;

       end;

       move(t_lnk[_odd],t_ins,k);      // wczytujemy blok relokowalny do T_INS
       inc(_odd,k);

       dlink.len:=k; dlink.use:=true; dlink.stc:=true;
   end;

      // BLK UPDATE ADDRESS
         __hea_address:
                begin
                 ch := chr( fgetB(_odd) );
                 j  := fgetW(_odd);

                 while j>0 do begin

                  idx_get:=fgetW(_odd);

                  tst:=adres;

                  case ch of

                   'E': begin                     // pusty blok rezerwujacy pamiec
                         dlink.emp := idx_get;
                        end;

                   '<','B':
                        begin
                         inc(tst, t_ins[idx_get]);

                         t_ins[idx_get]  := byte(tst);
                        end;

                   '>': begin
                         inc(tst, t_ins[idx_get] shl 8);

                         v:=fgetB(_odd);    // dodatkowy bajt dla relokacji starszych adresow

                         inc(tst, v);

                         t_ins[idx_get]  := byte(tst shr 8);
                        end;

                   'W': begin
                         inc(tst, t_ins[idx_get]);
                         inc(tst, t_ins[idx_get+1] shl 8);

                         t_ins[idx_get]  := byte(tst);
                         t_ins[idx_get+1]:= byte(tst shr 8);
                        end;

                   'L': begin
                         inc(tst, t_ins[idx_get]);
                         inc(tst, t_ins[idx_get+1] shl 8);
                         inc(tst, t_ins[idx_get+2] shl 16);

                         t_ins[idx_get]  := byte(tst);
                         t_ins[idx_get+1]:= byte(tst shr 8);
                         t_ins[idx_get+2]:= byte(tst shr 16);
                        end;

                   'D': begin
                         inc(tst, t_ins[idx_get]);
                         inc(tst, t_ins[idx_get+1] shl 8);
                         inc(tst, t_ins[idx_get+2] shl 16);
                         inc(tst, t_ins[idx_get+3] shl 24);

                         t_ins[idx_get]  := byte(tst);
                         t_ins[idx_get+1]:= byte(tst shr 8);
                         t_ins[idx_get+2]:= byte(tst shr 16);
                         t_ins[idx_get+3]:= byte(tst shr 24);
                        end;

                  end;

                  dec(j);
                 end;

                end;

      // BLK UPDATE EXTERNAL
         __hea_external:
                begin
                 ch := chr ( fgetB(_odd) );
                 j  := fgetW(_odd);

                 txt:=fgetS(_odd);           // label_ext name

                 idx_get:=load_lab(txt,false);
                 if idx_get<0 then begin
                  war:=0;
                  if pass=pass_end then blad_und(zm,txt,73);
                 end else
                  war:=oblicz_wartosc(txt,zm);

                 v:=ord(value_code(war,zm,true));

              // sprawdzamy czy zgadza sie typ etykiety
                 if pass=pass_end then
                  case ch of
                   'B': if chr(v)<>'Z' then blad_und(zm,txt,41);
                   'W': if not(chr(v) in ['Z','Q']) then blad_und(zm,txt,41);
                   'L': if not(chr(v) in ['Z','Q','T']) then blad_und(zm,txt,41);
                  end;


                 while j>0 do begin
                  idx_get:=fgetW(_odd);

                  tst:=word(war);

                  case ch of
                    'B','<':
                         begin
                          inc(tst, t_ins[idx_get]);

                          t_ins[idx_get]  := byte(tst);
                         end;

                   '>': begin
                         inc(tst, t_ins[idx_get] shl 8);

                         v:=fgetB(_odd);    // dodatkowy bajt dla relokacji starszych adresow

                         inc(tst,v);

                         t_ins[idx_get]  := byte(tst shr 8);
                        end;

                    'W': begin
                          inc(tst, t_ins[idx_get]);
                          inc(tst, t_ins[idx_get+1] shl 8);

                          t_ins[idx_get]  := byte(tst);
                          t_ins[idx_get+1]:= byte(tst shr 8);
                         end;

                    'L': begin
                          inc(tst, t_ins[idx_get]);
                          inc(tst, t_ins[idx_get+1] shl 8);
                          inc(tst, t_ins[idx_get+2] shl 16);

                          t_ins[idx_get]  := byte(tst);
                          t_ins[idx_get+1]:= byte(tst shr 8);
                          t_ins[idx_get+2]:= byte(tst shr 16);
                         end;

                    'D': begin
                          inc(tst, t_ins[idx_get]);
                          inc(tst, t_ins[idx_get+1] shl 8);
                          inc(tst, t_ins[idx_get+2] shl 16);
                          inc(tst, t_ins[idx_get+3] shl 24);

                          t_ins[idx_get]  := byte(tst);
                          t_ins[idx_get+1]:= byte(tst shr 8);
                          t_ins[idx_get+2]:= byte(tst shr 16);
                          t_ins[idx_get+3]:= byte(tst shr 24);
                         end;

                  end;

                  dec(j);
                 end;

                end;


      // BLK UPDATE PUBLIC
         __hea_public:
                begin
                 j:=fgetW(_odd);

                  while j>0 do begin

                   typ:= chr ( fgetB(_odd) );  // TYPE   B-YTE, W-ORD, L-ONG, D-WORD

                   ch := chr ( fgetB(_odd) );  // LABEL_TYPE   V-ARIABLE, P-ROCEDURE, C-ONSTANT

                   if dlink.use then tst:=adres else tst:=0;

                   case ch of
                    'P': begin
                          str:=fgetS(_odd);               // label_pub name

                          inc(tst, fgetW(_odd));          // adres procedury

                          r:=fgetB(_odd);                 // kolejnosc rejestrow CPU

                          rodzaj:=chr(fgetB(_odd));       // typ procedury

                          if not(rodzaj in [__pDef, __pReg, __pVar]) then blad_und(zm,str,41);

                          idx_get:=fgetW(_odd);           // liczba danych na temat parametrow


                          proc_nr:=proc_idx;         // koniecznie przez ADD_PROC_NR


                          if pass=0 then begin

                           _doo:=_odd+idx_get;

                           txt:='(';
                           while _odd<_doo do begin

                             v:=TypeToByte( chr( fgetB(_odd) ) );   // liczba bajtow przypadajaca na parametr

                             txt:=txt+mads_param[v];

                             case rodzaj of               // parametr jesli trzeba
                              __pDef: tmp:='par'+IntToStr(_odd);

                              __pReg: begin
                                       tmp:='';
                                       while v<>0 do begin
                                        tmp:=tmp+ByteToReg(r);
                                        dec(v)
                                       end;
                                      end;

                              __pVar: tmp:=fgetS(_odd);
                             end;

                             txt:=txt+tmp+' ';
                           end;

                           txt:=txt+')';

                           case rodzaj of
                            __pReg: txt:=txt+' .REG';
                            __pVar: txt:=txt+' .VAR';
                           end;

                           i:=1;
                           get_procedure(str,str,txt,i);    // odczytujemy parametry

                           proc:=false;                     // koniecznie wylaczamy PROC
                           proc_name:='';                   // i koniecznie PROC_NAME := ''

                          end else
                           inc(_odd,idx_get);    // koniecznie zwiekszamy _ODD gdy PASS<>0

                          upd_procedure(str,zm,tst);

                          proc:=false;           // koniecznie wylaczamy PROC
                          proc_name:='';         // i koniecznie PROC_NAME = ''

                          add_proc_nr;           // zwiekszamy koniecznie numer procedury
                         end;

               'A': begin                        // upubliczniamy .ARRAY
                      str:=fgetS(_odd);

                      _doo:= fgetW(_odd);

                      inc(tst, _doo);               // nowy adres etykiety

                      save_lab(str, array_idx, __id_array, zm);

                      save_arr(tst, bank);          // tutaj ARRAY_IDX zostaje zwiekszone o 1

                      _doo:= fgetW(_odd);

                      v:=TypeToByte( chr( fgetB(_odd) ) );

                      t_arr[array_idx-1].elm[0].cnt:=_doo; // dlatego teraz ARRAY_IDX-1

                      t_arr[array_idx-1].siz := v;
                      t_arr[array_idx-1].len := (_doo+1)*v;

                    end;

               'S': begin                        // upubliczniamy .STRUCT
                      str:=fgetS(_odd);

                      _doo:= fgetW(_odd);

                      upd_structure(str, zm);    // UPD_STRUCTURE ustawi wartosc STRUCT.IDX

                      zapisz_lokal;
                      lokal_name:=lokal_name+str+'.';

                      struct.adres:=0;

                      while _doo>0 do begin
                       v:=TypeToByte( chr( fgetB(_odd) ) );

                       str:=fgetS(_odd);

                       j:=fgetW(_odd);

                       save_str(str,struct.adres,v,j,adres,bank);
                       save_lab(str,struct.adres,bank,zm);

                       inc(struct.adres, v*j);

                       inc(struct.cnt);

                       dec(_doo);
                      end;

                      t_str[struct.idx].siz := struct.adres; // zapisujemy dlugosc struktury

                      t_str[struct.idx].ofs := struct.cnt;   // i liczbe pol struktury

                      inc(struct.id);  // zwiekszamy identyfikator struktury (liczba struktur)

                      struct.cnt := -1;

                      oddaj_lokal(zm);
                    end;

               'V': begin
                      str:=fgetS(_odd);

                      _doo:= fgetW(_odd);

                      inc(tst, _doo);                  // nowy adres etykiety

                      save_lab(str,tst,bank,zm);       // variable
                     end;

               'C': begin
                      str:=fgetS(_odd);

		      vtmp:=0;

                      case typ of
                       'B': vtmp:=fgetB(_odd);
                       'W': vtmp:=fgetW(_odd);
                       'L': vtmp:=fgetL(_odd);
                       'D': vtmp:=fgetD(_odd);
                      end;

                      save_lab(str,vtmp,bank,zm);      // constant
                    end;

                   end;


                   dec(j);
                  end;

                 end;
        else

   begin
     flush_link;

     k:=fgetW(_odd);              // odczytujemy dlugosc pliku relokowalnego
     inc(k);                      // zwiekszamy o 1

     testRange(zm,k, 62);         // maksymalna dlugosc pliku $FFFF

     save_hea;
     adres:=j; org:=true;

     dlink.len:=k-j;

     move(t_lnk[_odd],t_ins,dlink.len);      // wczytujemy blok relokowalny do T_INS
     inc(_odd,dlink.len);
   end;

        end;



 end;

       flush_link;

       closefile(g);

       ety:='';
      end;


(*----------------------------------------------------------------------------*)
(*  .PUBLIC label [,label2,label3...]                                         *)
(*----------------------------------------------------------------------------*)
   __public:
    if ety<>'' then blad(zm,38) else
     if macro_rept_if_test then begin

       save_lst(' ');

       omin_spacje(i,zm);

       while not(test_char(i,zm)) do begin

        txt:=get_lab(i,zm, true);

        save_pub(txt,zm);

        _odd:=load_lab(txt,false);
        if _odd>=0 then t_lab[_odd].use:=true;     //etykieta domyslnie w uzyciu

        __next(i,zm);
       end;

      end;


(*----------------------------------------------------------------------------*)
(*  .SYMBOL label                                                             *)
(*----------------------------------------------------------------------------*)
 __symbol:
    if macro_rept_if_test then
     if not(dreloc.sdx) then blad(zm,53) else begin   // tylko gdy blok relokowalny SDX

       if ety='' then ety:=get_lab(i,zm, true);

       if not(test_char(i,zm)) then blad(zm,4);

       save_lst(' ');

      // zapisujemy symbol .SYMBOL w T_SYM
       t_sym[sym_idx] := ety;                                  // SAVE_SYM
       inc(sym_idx);                                           //
       if sym_idx>High(t_sym) then SetLength(t_sym,sym_idx+1); //

     end;


(*----------------------------------------------------------------------------*)
(*  INS 'filename' [+-expression] [,length[,offset]]                          *)
(*  .GET [index] 'filename' [+-expression] [,length[,offset]]                 *)
(*----------------------------------------------------------------------------*)
   __ins, __get, __xget:
     if macro_rept_if_test then
//      if loop_used then blad(zm,36) else
       if first_org and (opt and opt_H>0) and (mne.l=__ins) then blad(zm,10) else begin

         data_out:=true;

         idx_get:=0;

         omin_spacje(i,zm);

         if mne.l=__get then
          if zm[i] in AllowStringBrackets then begin
           txt:=ciag_ograniczony(i,zm,true);
           k:=1; idx_get:=integer( oblicz_wartosc_noSPC(txt,zm,k,#0,'A') );
          end;

//         omin_spacje(i,zm);
         txt:=get_string(i,zm,zm,true);

         txt:=GetFile(txt,zm);   if not(TestFile(txt)) then blad(txt,18);

         if (GetFileName(txt)=GetFileName(a)) or (GetFileName(txt)=GetFileName(plik_asm)) then blad(txt,18);

         AssignFile(g, txt); FileMode:=0; Reset(g,1);

         k:=integer(FileSize(g)); _odd:=0; _doo:=k;

         v:=byte( test_string(i,zm,'B') );

         if zm[i]=',' then begin
          __inc(i,zm);

          _odd:=integer( oblicz_wartosc_noSPC(zm,zm,i,',','F') );

          if _odd<0 then begin
           _doo:=abs(_odd); _odd:=k+_odd;
          end else _doo:=k-abs(_odd);

          if zm[i]=',' then begin
           __inc(i,zm);

           _doo:=integer( oblicz_wartosc_noSPC(zm,zm,i,',','F') );
// -           testRange(zm, _doo, 13);
           if _doo<0 then begin
            blad(zm,13);
            _doo:=0;
           end;

           test_eol(i,zm,zm,#0);
          end;
         end else test_eol(i,zm,zm,#0);

        // sprawdz czy nie zostala przekroczona dlugosc pliku
         if (abs(_odd)>k) or (abs(_odd)+abs(_doo)>k) then blad(zm,24);
         k:=_doo;


        // dlugosc pliku nie moze byc mniejsza od 0
// -         testRange(zm, k, 25); //if k>$FFFF then blad(zm,25);
         if k<0 then begin
          blad(zm,25);
          k:=0;
         end;


         save_lst('a');

         if mne.l in [__get, __xget] then begin // .GET

           j:=idx_get+_doo;
           testRange(zm, j, 62);  // subrange_bounds(zm,idx_get+_doo,$FFFF+1);

           if _odd>0 then seek(g,_odd);         // omin _ODD bajtow w pliku
           blockread(g, t_get[idx_get], _doo);  // odczytaj _DOO bajtow od indeksu [IDX_GET]

           if mne.l = __xget then begin

            for j := 0 to _doo-1 do
             if t_get[idx_get+j] <> 0 then t_get[idx_get+j] := t_get[idx_get+j] + v;

           end else
            for j := 0 to _doo-1 do t_get[idx_get+j] := t_get[idx_get+j] + v;

         end else                               // INS
         if (pass=pass_end) and (_doo>0) then begin

//           if opt and opt_H=0 then first_org := true;

           if _odd>0 then seek(g,_odd);         // omin _ODD bajtow w pliku

           for j:=0 to (_doo div $10000)-1 do begin
            blockread(g, t_ins, $10000);        // odczytaj 64KB bajtow
            for idx:=0 to $FFFF do save_dst( byte( t_ins[idx]+v ) );
           end;

           j:=_doo mod $10000;                  // odczytaj pozostale bajty

           blockread(g, t_ins, j);

           for idx:=0 to j-1 do save_dst( byte( t_ins[idx]+v ) );
         end;

         closefile(g);

         save_lab(ety,adres,bank,zm);

         if not(mne.l in [__get, __xget]) then inc(adres, k);
         ety:='';
        end;


(*----------------------------------------------------------------------------*)
(*  END                                                                       *)
(*----------------------------------------------------------------------------*)
   __end, __en:
        if loop_used then blad(zm,36) else begin

          end_file:=true;

          save_lab(ety,adres,bank,zm);

          save_lst('a');

          mne.l:=0;
          ety:='';
        end;


(*----------------------------------------------------------------------------*)
(*  DTA [abefgtcd] 'string',expression...                                     *)
(*  lub dodajemy nowe pola do struktury .STRUCT                               *)
(*----------------------------------------------------------------------------*)
   __dta, __byte..__dword:
        if macro_rept_if_test then
         if first_org and (opt and opt_H>0) and not(struct.use) then blad(zm,10) else begin

          defaultZero := (mne.l <> __dta);

          if struct.use then begin              // zapisujemy pola struktury

           omin_spacje(i,zm);

           if zm[i]=':' then begin              // dla skladni .byte :5 label
            inc(i);
            txt:=get_dat(i,zm,',',true);
            _doo:=integer( oblicz_wartosc(txt,zm) );
            testRange(zm, _doo, 0);

            loop_used:=true;
            rpt:=_doo;
           end;

           if ety='' then get_parameters(i,zm,par,false, '.',#0);    // tutaj nie moze konczyc odczytu dla ':', np.: .BYTE :5 LABEL

	   if High(par) = 0 then blad(zm,58);

           omin_spacje(i,zm);
           test_eol(i,zm,zm,#0);

           for idx := 0 to High(par) - 1 do begin

            ety:=par[idx];

            if (ety='') or not(_lab_first(ety[1])) then blad(zm,58{15});         // pola struktury musza posiadac etykiety
            if mne.l=__dta then blad(zm,58);    // przyjmujemy tylko nazwy typow

            j:=mne.l-__byteValue;               // J = <1..4>
            k:=adres-struct.adres;

            if ety+'.'=lokal_name then blad(zm,57);  // nazwa pola musi byc <> od nazwy struktury

            save_str(ety,k,j,rpt,adres,bank);
            save_lab(ety,k,bank,zm);

            nul.i:=k;
            save_lst('l');

            if loop_used then begin
             //loop_used:=false;
             j := j*rpt;
            end;

            inc(adres, j);

            inc(struct.cnt);                    // zwiekszamy licznik pol struktury

           end;

          end else
           create_struct_data(i,zm,ety, mne.l);

          loop_used:=false;

          ety:='';
         end;


(*----------------------------------------------------------------------------*)
(*  ICL 'filename'                                                            *)
(*----------------------------------------------------------------------------*)
   __icl:
       if macro_rept_if_test then
        if loop_used then blad(zm,36) else begin

          save_lab(ety,adres,bank,zm);
          save_lst('a');

          txt:=get_string(i,zm,zm,true);

          txt:=GetFile(txt,zm);

          if not(TestFile(txt)) then begin
           tmp:=GetFile(txt+'.asm', zm);

           if not(TestFile(tmp)) then
            blad(txt,18)
           else
            txt:=tmp;

          end;

          test_eol(i,zm,zm,#0);

//          if (GetFileName(txt)=GetFileName(a)) or (GetFileName(txt)=GetFileName(plik_asm)) then blad(txt,18);
          if (txt=a) or (txt=plik_asm) then blad(txt,18);

        // sprawdzamy czy jest to plik tekstowy w pierwszych dwóch przebiegach asemblacji
          if pass<2 then begin
           assignfile(f, txt); FileMode:=0; Reset(f);
           readln(f, tmp);
           CloseFile(f);
           if pos(#0,tmp)>0 then blad(zm,74);
          end;

          str:=zm; zapisz_lst(str);


          old_icl_used := icl_used;
          icl_used:=true;

          analizuj_plik(txt,zm);

          bez_lst:=true;
//          put_lst(show_full_name(a,full_name,true),'');
          global_name:=a;

          line:=nr;

          icl_used := old_icl_used;


          ety:='';
          mne.l:=0;

         end;


(*----------------------------------------------------------------------------*)
(*  .SEGDEF label, address, length, [attrib, [bank]]                          *)
(*----------------------------------------------------------------------------*)
   __segdef:
   if macro_rept_if_test then
    if loop_used then blad(zm,36) else
     if ety<>'' then blad(zm,38) else begin

      save_lst('a');

      get_parameters(i,zm,par,false);

      _doo:=High(par);

      if (_doo>=3) and (_doo<=5) then begin     // wymagane co najmniej 3 parametry

       for idx:=0 to _doo-1 do
        if par[idx]='' then blad(zm,23);

      end else
       blad(zm,58);

      k:=-1;                                    // sprawdzamy czy juz mamy ta etykiete
      for idx:=High(t_seg)-1 downto 1 do
       if t_seg[idx].lab=par[0] then begin
        k:=idx;
        Break;
       end;

      if k<0 then begin                         // pierwsze wystapienie etykiety
       idx:=High(t_seg);                        // dopiszemy do listy
       SetLength(t_seg, idx+2);
      end else
       if t_seg[idx].pas=pass then blad_und(zm,par[0],2);


       t_seg[idx].pas:=pass;                    // numer przebiegu

       t_seg[idx].lab:=par[0];                  // etykieta segmentu

       tmp:=par[1];                             // adres poczatkowy segmentu
       war:=oblicz_wartosc(tmp, zm);            //
       t_seg[idx].start:=war;                   //
       t_seg[idx].adr:=war;                     //

       tmp:=par[2];                             // dlugosc segmentu
       war:=oblicz_wartosc(tmp, zm);            //
       t_seg[idx].len:=war;                     //

       v:=ord(__RW);                            // Read/Write

       if _doo>=4 then
        if par[3]='RW' then v:=ord(__RW) else
         if par[3]='R' then v:=ord(__R) else
          if par[3]='W' then v:=ord(__W) else
           blad(zm,58);

       t_seg[idx].atr:=t_Attrib(v);             // atrybut segmentu

       if _doo=5 then begin
        tmp:=par[4];                            // bank segmentu, jeśli brak to 0
        war:=oblicz_wartosc(tmp, zm);           //
        t_seg[idx].bnk:=war;                    //
       end else
        t_seg[idx].bnk:=0;


      if pass=pass_end then                    // !!! koniecznie !!!
       for k:=High(t_seg)-1 downto 1 do
        if k<>idx then
         if (t_seg[idx].bnk=t_seg[k].bnk) then
          if (t_seg[k].start<=t_seg[idx].start) and (t_seg[k].start+t_seg[k].len-1>=t_seg[idx].start) then blad(zm,117);

      ety:='';
     end;


(*----------------------------------------------------------------------------*)
(*  .SEGMENT label                                                            *)
(*----------------------------------------------------------------------------*)
    __segment:
   if macro_rept_if_test then
    if loop_used then blad(zm,36) else
     if ety<>'' then blad(zm,38) else begin

      save_lst('a');
      bez_lst:=true;

      txt:=get_lab(i, zm, true);

      k:=-1;

      for idx:=High(t_seg)-1 downto 1 do
       if t_seg[idx].lab=txt then begin
        k:=idx;
        Break;
       end;

      if k>=0 then begin

       if adres<0 then                          // jesli nie bylo ORG-a
        t_seg[segment].adr := t_seg[segment].start
       else
        t_seg[segment].adr := adres;

       t_seg[segment].bnk := bank;
       t_seg[segment].atr := atr;

       txt:=' org $'+hex(t_seg[k].adr,4);

       idx:=line_add;
       line_add:=line-1;

       _odd:=High(t_mac);                       // procedura z parametrami
       t_mac[_odd]:=txt;                        // wymuszamy wykonanie większej liczby linii
       _doo:=_odd+1;
       analizuj_mem(_odd,_doo, zm,a,old_str, 0,1, false);

       line_add:=idx;

       segment:=k;
       bank := t_seg[k].bnk;

       atr := t_seg[k].atr;

      end else
       blad_und(zm,txt,5);                      // nie ma takiego segmentu

    end;


(*----------------------------------------------------------------------------*)
(*  .ENDSEG                                                                   *)
(*----------------------------------------------------------------------------*)
   __endseg:
   if macro_rept_if_test then
    if loop_used then blad(zm,36) else
     if ety<>'' then blad(zm,38) else begin

       save_lst('a');
       bez_lst:=true;

       t_seg[segment].adr := adres;
       t_seg[segment].bnk := bank;
       t_seg[segment].atr := atr;

       txt:=' org $'+hex(t_seg[0].adr,4);

       segment:=0;
       bank := t_seg[0].bnk;
       atr  := t_seg[0].atr;

       idx:=line_add;
       line_add:=line-1;

       _odd:=High(t_mac);                       // procedura z parametrami
       t_mac[_odd]:=txt;                        // wymuszamy wykonanie większej liczby linii
       _doo:=_odd+1;
       analizuj_mem(_odd,_doo, zm,a,old_str, 0,1, false);

       line_add:=idx;

       if pass=pass_end then
        for k:=High(t_seg)-1 downto 1 do
          if t_seg[k].bnk=bank then
           if (t_seg[k].start<adres) and (t_seg[k].start+t_seg[k].len-1>=adres) then warning(117);

     end;


(*----------------------------------------------------------------------------*)
(*  #CYCLE cycle                                                              *)
(*----------------------------------------------------------------------------*)
   __cycle:
   if macro_rept_if_test then
    if loop_used then blad(zm,36) else
    { if ety<>'' then blad(zm,38) else }begin

      if ety<>'' then save_lab(ety,adres,bank,zm);
      ety:='';

      omin_spacje(i,zm);

      if zm[i]='#' then
       __inc(i,zm)
      else
       blad(zm,14);

      _doo:=integer( oblicz_wartosc_noSPC(zm,zm,i,#0,'A') );
      if _doo<2 then blad(zm,0,'('+IntToStr(_doo)+' must be between 2 and 65535)');

      save_lst('a');

      while _doo>0 do begin

       if _doo<=10 then idx:=_doo else
        if _doo mod 10<2 then idx:=2 else
         idx:=_doo mod 10;

       case idx of
         2: begin save_dst($ea); inc(adres) end;						// NOP
         3: begin save_dst($c5); save_dst(0); inc(adres,2) end;					// CMP Z
         4: begin save_dst($ea); save_dst($ea); inc(adres,2) end;				// NOP:NOP
         5: begin save_dst($c5); save_dst(0); save_dst($ea); inc(adres,3) end;			// CMP Z:NOP
         6: begin save_dst($c1); save_dst(0); inc(adres,2) end;					// CMP (Z,X)
         7: begin save_dst($48); save_dst($68); inc(adres,2) end;				// PHA:PLA
         8: begin save_dst($c1); save_dst(0); save_dst($ea); inc(adres,3) end;			// CMP (Z,X):NOP
         9: begin save_dst($48); save_dst($68); save_dst($ea); inc(adres,3) end;		// PHA:PLA:NOP
        10: begin save_dst($48); save_dst($68); save_dst($c5); save_dst(0); inc(adres,4) end;	// PHA:PLA:CMP Z
       end;

       dec(_doo, idx);
      end;

     end;

  end;


 // zapamietanie etykiety jesli wystapila
 // i zapisanie zdekodowanych rozkazow
  if if_test then begin

   omin_spacje(i,zm);
   txt:=''; search_comment_block(i,zm,txt);

   if ety<>'' then begin

    if aray then blad(zm, 58);

//    if mne_used then

     label_type:='V';          // !!! koniecznie label_type = V-ariable

//    else
//     label_type:='C';

    if pass=pass_end then
     if adres<0 then warning(10);

    save_lab(ety,adres,bank,zm);   // pozostale etykiety bez zmian

    save_lst('a');
   end;


//   writeln(zm,' | ',if_test);


   if mne.l<__equ then begin

    nul:=mne;

    if (mne.l=0) and (ety='') then
     save_lst(' ')
    else
     save_lst('a');

    nul.l:=0;
   end;

  end;


 // zapisz wynik asemblacji do pliku LST

  if not(loop_used) and not(FOX_ripit) then begin

   if not(bez_lst) then zapisz_lst(zm);


   bez_lst:=false;
 end;


 if runini.use then begin   // RUN, INI zachowają aktualny adres asemblacji
  save_hea;
  adres:=runini.adr;
  runini.use:=false;
  new_DOS_header;
 end;

end;


procedure get_line(var zm:string; var end_file,ok:Boolean; var _odd,_doo:integer; var app: Boolean; var appLine: string);
(*----------------------------------------------------------------------------*)
(*  pobieramy linie i sprawdzamy czy linia nie jest komentarzem               *)
(*----------------------------------------------------------------------------*)
var i, j: integer;
    str: string;
begin
   if end_file then exit;

    noWarning:=false;

   if not(macro) {and not(rept)} then        // dla kodu w bloku REPT     */ NOP
    if komentarz then begin
     i:=1;
     str:=''; search_comment_block(i,zm,str);

     if str<>'' then begin
       save_lst(' ');
       justuj;
       put_lst(t+zm);

       zm:=copy(zm,i,length(zm));
      end;

    end;


    if not(komentarz) then
    if not(macro) and not(rept) and (pos('\',zm)>0) then begin   // pobieżny test na obecnosc znaku '\'
     i:=1;
     str:=get_dat(i,zm,'\',false);                 // tutaj sprawdzamy dokladniej

     SetLength(t_lin, 1);

     if zm[i]='\' then begin
       save_lst(' ');
       justuj;
       put_lst(t+zm);

       _odd:=High(t_lin);
       i:=1;
       while true do begin
        str:=get_dat(i,zm,'\',false);

        j:=1; omin_spacje(j, str);
        if j>length(str) then str:='';

        j:=High(t_lin);       // SAVE_LIN
        t_lin[j]:=str;        //
        SetLength(t_lin,j+2); //

        if zm[i]='\' then inc(i) else Break;
       end;

       _doo:=High(t_lin);


       if str='' then begin
        app:=true;

        appLine:=appLine+t_lin[_doo-2];

        dec(_doo,2);
       end;


       lst_off:=true;

       ok:=false;
       exit;
     end;

    end;


   app:=false;

   i:=1;

   if zm<>'' then begin
    omin_spacje(i,zm);

    if not((zm[i] in [';','*']) or ((zm[i]='|') and (zm[i+1]<>'|'))  or komentarz) then ok:=true;

    str:=''; search_comment_block(i,zm, str);
   end;


// !!! linie z komentarzem /* */ byly traktowane jako puste linie !!!

{ omin_spacje(i,zm);                // sprawdzamy czy wiersz nie zawiera samych "bialych znakow"

 if not(macro) and not(rept) then
  if (i>length(zm)) then begin
   ok:=false;

   if not(komentarz) then zm:='';  // jesli nie jest to komentarz to zapiszemy tylko pusty wiersz
  end;  }


 if not(macro) and not(rept) and not(run_macro) and not(rept_run) then
  if (zm='') or not(ok) then begin
   save_lst(' ');

   if zm<>'' then
    justuj
   else
    SetLength(t,6);

   put_lst(t+zm);

   ok:=false;
  end;

end;


procedure analizuj_plik(var a:string; var old_str: string);
(*----------------------------------------------------------------------------*)
(*  odczyt pliku ASM wiersz po wierszu                                        *)
(*----------------------------------------------------------------------------*)
var f: textfile;
    nr, _odd, _doo: integer;
    end_file, ok, wyjscie, app, _app: Boolean;
    zm, appLine, _appLine: string;
    v: byte;
begin
 if not(TestFile(a)) then blad(a,18);

 AssignFile(f,a); FileMode:=0; Reset(f);

 _odd:=0; _doo:=0;

 nr:=0;                        // nr linii w asemblowanym pliku
 global_name:=a;               // nazwa pliku dla funkcji 'BLAD'
 end_file:=false;              // czy napotkal rozkaz 'END'
 wyjscie:=false;               // czy wystapilo EXIT w makrze

 app:=false; appLine:='';
 _app:=false; _appLine:='';


 // nazwe pierwszego pliku zawsze zapisze do LST
 // pod warunkiem ze (opt and  opt_L>0) czyli wystapilo OPT L+
 if (opt and opt_L>0) then
  if (pass=pass_end) and (GetFilePath(a) <> '') then
//   writeln(lst,show_full_name(global_name,true,true))
//  else
   lst_string:=show_full_name(global_name,full_name,true);


 while (not eof(f)) or (_doo>0) do begin

  ok:=false;

  if _doo>0 then begin
   zm:=t_lin[_odd];
   inc(_odd);
   if _odd>=_doo then begin _doo:=0; lst_off:=false; SetLength(t_lin, 0) end;

   get_line(zm,end_file,ok,_odd,_doo, _app,_appLine);

  end else begin
   readln(f,zm);

   if length(zm)>$FFFF then begin       // maksymalna dlugosc wiersza 65535 znakow
    blad(zm,101); koniec(2)
   end;

   inc(nr); line:=nr; inc(line_all);

   get_line(zm,end_file,ok,_odd,_doo, app,appLine);

   if ok and not(app) and (appLine<>'') then begin
    save_lst(' ');
    justuj;
    put_lst(t+zm);

    zm:=appLine+zm;
    appLine:='';
   end;

  end;


  if macro then begin                              // zapis bloku .MACRO
   v:=dirMACRO(zm);

   if v in [{__end+1,} __en] then end_file:=true;  // !!! dla __end+1 zatrzyma sie gdy 'end \ lda end'

  end else

    if rept then begin                             // zapis bloku .REPT

     if ok and not(komentarz) then
      v:=dirREPT(zm)
     else
      v:=0;

     if (v in [__endr, __dend]) and (rept_cnt=0) then
      dirENDR(zm,a,old_str, 0)
     else
      if v in [__end+1, __en] then end_file:=true;

    end else

     if ok and not(komentarz) then
      analizuj_linie(zm,a,old_str, nr, end_file,wyjscie);


  if end_file then Break;

 end;


 if appLine<>'' then analizuj_linie(appLine,a,old_str, nr, end_file,wyjscie);


 test_skipa;
 if skip_use then blad(zm,84);             // Can't skip over this


 oddaj_var;

 if a=plik_asm then oddaj_ds;  // !!! koniecznie tutaj, inaczej po ICL z .DS bedzie generowal nowy blok EMPTY


 if pass=pass_end then
 if (a=plik_asm) {and not(first_org)} then begin    // wymuszamy BLK UPDATE na koncu glownego pliku

  if dreloc.use or dreloc.sdx then begin

   save_lst('a');
   if not(blkupd.adr) then begin zm:=load_mes(91)+load_mes(92); blk_update_address(zm) end;
   save_lst('a');
   if not(blkupd.ext) then begin zm:=load_mes(91)+load_mes(93); blk_update_external(zm) end;
   save_lst('a');
   if not(blkupd.pub) then begin zm:=load_mes(91)+load_mes(94); blk_update_public(zm) end;
   save_lst('a');
   if not(blkupd.sym) then begin zm:=load_mes(91)+load_mes(95); blk_update_symbol(zm) end;
   save_lst('a');

   oddaj_sym;

  end;

 end;


 test_wyjscia(zm,wyjscie);

 closefile(f);
end;



procedure analizuj_mem(const start,koniec:integer; var old,a,old_str:string; licz:integer; const p_max:integer; const rp:Boolean);
(*----------------------------------------------------------------------------*)
(*  odczyt i analiza wierszy zapisanych w tablicy dynamicznej T_MAC           *)
(*  P_MAX okresla liczbe powtorzen                                            *)
(*----------------------------------------------------------------------------*)
var licznik, nr, _odd, _doo, old_line_add: integer;
    end_file, ok, wyjscie, old_icl_used, app, _app: Boolean;
    zm, appLine, _appLine: string;
    v: byte;
begin

 old_icl_used := icl_used;
 icl_used     := true;

 old_line_add := line_add;     // !!! koniecznie zapamietac LINE_ADD !!!
 line_add     := 0;            // inaczej numer linii z bledem dla np. "lda:cmp:rq" bedzie zly


 _odd:=0; _doo:=0;

 while licz < p_max do begin

 if rp or FOX_ripit then ___rept_ile := licz;

 licznik:=start;

 nr:=old_line_add;             // nr linii w asemblowanym pliku
 end_file:=false;              // czy napotkal rozkaz 'END'
 wyjscie:=false;               // czy wystapilo EXIT w makrze

 app:=false; appLine:='';
 _app:=false; _appLine:='';


 while (licznik<koniec) or (_doo>0) do begin

  ok:=false;

  if _doo>0 then begin

   zm:=t_lin[_odd];
   inc(_odd);
   if _odd>=_doo then begin _doo:=0; lst_off:=false; SetLength(t_lin, 0) end;

   get_line(zm,end_file,ok, _odd,_doo, _app,_appLine);

  end else begin
   zm:=t_mac[licznik];

   reptLine(zm);       // podstawiamy parametry w bloku .REPT

   inc(licznik);

   inc(nr);
   line:=nr;

   inc(line_all);

   get_line(zm,end_file,ok, _odd,_doo, app,appLine);

   if ok and not(app) and (appLine<>'') then begin
    save_lst(' ');
    justuj;
    put_lst(t+zm);

    zm:=appLine+zm;
    appLine:='';
   end;

  end;


   if rept then begin                   // zapis bloku .REPT

     if ok and not(komentarz) then
      v:=dirREPT(zm)
     else
      v:=0;

     if (v in [__endr, __dend]) and (rept_cnt=0) then
      dirENDR(zm,a,old_str, 0)
     else
      if v in [__end+1, __en] then end_file:=true;

   end else

    if ok and not(end_file) and not(komentarz) then
     analizuj_linie(zm,a,old_str, nr, end_file,wyjscie);


  if wyjscie then Break;          // zakonczenie przetwarzania makra przez dyrektywe .EXIT

 end;


 if appLine<>'' then analizuj_linie(appLine,a,old_str, nr, end_file,wyjscie);

 inc(licz);
 end;


 test_wyjscia(old,wyjscie);

 icl_used := old_icl_used;
 line_add := old_line_add;
end;


procedure asem(var a:string);
(*----------------------------------------------------------------------------*)
(*  asemblacja glownego pliku *.ASM                                           *)
(*----------------------------------------------------------------------------*)
var i: integer;
    s: string;
begin

 while (pass<=pass_end) {and (pass<pass_max)} do begin   // maksymalnie PASS_MAX przebiegow

  line_all:=0;

  s:='';
  analizuj_plik(a, s);

  if list_mac then begin
   s:=' icl '''+plik_mac+'''';
   analizuj_plik(plik_mac, s);
  end;

  t_hea[hea_i]:=adres-1;           // koniec programu, ostatni wpis

  inc(pass);

 // jesli NEXT_PASS = TRUE to zwieksz liczbe przebiegow
  if (pass>=pass_end) or (pass<1) then
   if next_pass then inc(pass_end);


 // !!! zerowanie numeru wywolania makra !!!
  for i:=High(t_lab)-1 downto 0 do
   if t_lab[i].bnk=__id_macro then t_mac[ t_lab[i].adr + 3 ] := '0';

  label_type:='V';

  zpvar:=$80;

  adres:=-$FFFF; raw.old:=-$FFFF;

  t_seg[0].adr:=-$ffff;

  hea_ofs.old:=0;
  hea_ofs.adr:=-1; struct.cnt:=-1; ___rept_ile:=-1;

  regOpty.reg[0]:=-1; regOpty.reg[1]:=-1; regOpty.reg[2]:=-1;

  fillchar(t_zpv, sizeof(t_zpv), false);

  array_used.max:=0;

  hea_i:=0; bank:=0; ifelse:=0; blok:=0; rel_ofs:=0; org_ofset:=0;
  proc_idx:=0; proc_nr:=0; lokal_nr:=0; lc_nr:=0; fill:=0;
  line_add:=0; struct.id:=0; wyw_idx:=0; rel_idx:=0;
  ext_idx:=0; extn_idx:=0; smb_idx:=0; sym_idx:=0; skip_idx:=0;
  pag_idx:=0; end_idx:=0; pub_idx:=0; usi_idx:=0; segment:=0;
  whi_idx:=0; while_nr:=0; ora_nr:=0; test_nr:=0; proc_lokal:=0;
  test_idx:=0; var_idx:=0; var_id:=0; rept_cnt:=0; anonymous_idx:=0;

  __link_stack_pointer := adr_label(__STACK_POINTER, false);       // @STACK_POINTER
  __link_stack_address := adr_label(__STACK_ADDRESS, false);       // @STACK_ADDRESS
  __link_proc_vars_adr := adr_label(__PROC_VARS_ADR, false);       // @PROC_VARS_ADR

  siz_idx:=1;
  array_idx:=1;         // pierwszy wpis zarezerwowany dla .PUT

  opt := optDefault;
  atr := atrDefault;

  hea:=true; first_org:=true; if_test:=true; TestWhileOpt:=true;
  exProcTest:=true;

  regOpty.use:=false; regOpty.blk:=false; mae_labels:=false;
  loop_used:=false; macro:=false; proc:=false; regAXY_opty:=false;
  undeclared:=false; xasmStyle:=false;
  icl_used:=false; bez_lst:=false; empty:=false; enum.use:=false;
  reloc:=false; branch:=false; vector:=false; rept:=false; rept_run:=false;
  struct.use:=false; dta_used:=false; code6502:=false;
  struct_used.use:=false; aray:=false; next_pass:=false;
  mne_used:=false; skip_use:=false; skip_xsm:=false; FOX_ripit:=false;
  put_used:=false; ext_used.use:=false; dreloc.use:=false; dreloc.sdx:=false;
  rel_used:=false; blocked:=false; dlink.stc:=false;
  blokuj_zapis:=false; overflow:=false; test_symbols:=false;
  lst_off:=false; noWarning:=false; raw.use:=false; variable:=false;

  komentarz:=false; org:=false; runini.use:=false;

  lokal_name:=''; macro_nr:=''; while_name:=''; test_name:='';

  warning_old:='';

  SetLength(t_lin, 1);              // T_LIN mozemy zapisywac od nowa

  if binary_file.use then begin
   adres     := binary_file.adr;
   org       := true;
   first_org := false;
  end;

 end;

 if pass>pass_max then warning(119);

 // jesli nie wystapil zaden blad i mamy 16 przebiegow to na pewno nastapila petla bez konca

end;


procedure Syntax;
(*----------------------------------------------------------------------------*)
(*  wyswietlamy informacje na temat przelacznikow, konfiguracji MADS'a        *)
(*----------------------------------------------------------------------------*)
var s: string;
begin
 TextColor(WHITE);
 Writeln(Tab2Space(load_mes(mads_version)));

 TextColor(DARKGRAY);
 Writeln(Tab2Space(load_mes(mads_version-2)));
 NormVideo;

 halt(3);
end;


function NewFileExt(nam: string; const ext: string): string;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
begin

 if pos('.',nam)>0 then begin
  obetnij_kropke(nam);
  Result:=nam+ext;
 end else
  Result:=nam+'.'+ext;

end;


function nowy_plik(var a: string; var i:integer): string;
(*----------------------------------------------------------------------------*)
(*----------------------------------------------------------------------------*)
var name, path: string;
begin

 path:='';

 Result:=a;

 inc(i, 2);                          // omijamy znak przelacznika i znak ':'

 name:=copy(t,i,length(t));

 if GetFilePath(name)<>'' then path:=GetFilePath(name);

 if name<>'' then Result:=path+GetFileName(name);

 inc(i,length(name));
end;


procedure INITIALIZE;
(*----------------------------------------------------------------------------*)
(*  procedura obliczajaca tablice CRC16, CRC32, mniej miejsca zajmuje anizeli *)
(*  gotowa predefiniowana tablica                                             *)
(*----------------------------------------------------------------------------*)
var IORes, _i, x, y: integer;
    crc: cardinal;
    crc_: Int64;
    tmp: string;

const

 // _HASH wylicza osobny program
 // nie trzeba przechowywac w pamieci stringow z nazwami
 _hash: array [0..345] of record
                              v: byte;
                              o: word;
                         end =
 (
 (v:$58;o:$0458),(v:$01;o:$048C),(v:$5A;o:$04A4),(v:$44;o:$04B0),(v:$1E;o:$0510),(v:$70;o:$0513),
 (v:$DA;o:$051C),(v:$1F;o:$0590),(v:$E9;o:$059E),(v:$5B;o:$05C9),(v:$F0;o:$060E),(v:$3E;o:$0642),
 (v:$0E;o:$064F),(v:$86;o:$0684),(v:$A0;o:$068A),(v:$04;o:$0693),(v:$9E;o:$06CD),(v:$9E;o:$06ED),
 (v:$29;o:$0714),(v:$2A;o:$0734),(v:$06;o:$0766),(v:$98;o:$0853),(v:$98;o:$0881),(v:$45;o:$0910),
 (v:$4A;o:$0990),(v:$8D;o:$09AC),(v:$89;o:$09AE),(v:$8C;o:$09B2),(v:$93;o:$09B3),(v:$97;o:$0A03),
 (v:$3C;o:$0A54),(v:$CA;o:$0A68),(v:$68;o:$0A69),(v:$3D;o:$0A74),(v:$D3;o:$0A82),(v:$9D;o:$0AB3),
 (v:$0A;o:$0C53),(v:$33;o:$0C62),(v:$9F;o:$0C6A),(v:$9B;o:$0C72),(v:$9B;o:$0C73),(v:$07;o:$0C81),
 (v:$52;o:$0C94),(v:$12;o:$0CA4),(v:$22;o:$0CB3),(v:$18;o:$0D83),(v:$69;o:$0DC1),(v:$13;o:$0DC9),
 (v:$53;o:$0E74),(v:$36;o:$0EC2),(v:$9F;o:$0ECA),(v:$9B;o:$0ED2),(v:$9B;o:$0ED3),(v:$EB;o:$0EF2),
 (v:$DF;o:$0FA5),(v:$50;o:$1074),(v:$9D;o:$1081),(v:$9C;o:$10A4),(v:$24;o:$10B3),(v:$16;o:$10F4),
 (v:$46;o:$1110),(v:$1B;o:$1183),(v:$4B;o:$1190),(v:$08;o:$11C1),(v:$85;o:$11C5),(v:$9C;o:$11C9),
 (v:$97;o:$1203),(v:$64;o:$1252),(v:$BC;o:$1284),(v:$59;o:$1478),(v:$63;o:$155E),(v:$6C;o:$15C1),
 (v:$32;o:$15C2),(v:$9F;o:$15CA),(v:$9B;o:$15D2),(v:$9B;o:$15D3),(v:$63;o:$166C),(v:$10;o:$16BF),
 (v:$05;o:$182B),(v:$A2;o:$1925),(v:$63;o:$1A4F),(v:$A2;o:$1B79),(v:$65;o:$1C4B),(v:$83;o:$1E4F),
 (v:$B9;o:$1EE6),(v:$B6;o:$1EE7),(v:$F0;o:$20ED),(v:$68;o:$2258),(v:$CD;o:$22D8),(v:$56;o:$2437),
 (v:$43;o:$24B0),(v:$23;o:$24B3),(v:$0F;o:$254F),(v:$19;o:$2583),(v:$AA;o:$2585),(v:$31;o:$25A2),
 (v:$9F;o:$25AA),(v:$9B;o:$25B2),(v:$9B;o:$25B3),(v:$8A;o:$25C9),(v:$67;o:$266F),(v:$20;o:$2692),
 (v:$AC;o:$2760),(v:$DB;o:$2C0A),(v:$6B;o:$2C28),(v:$0B;o:$2C9D),(v:$47;o:$2D10),(v:$94;o:$2D82),
 (v:$17;o:$2E42),(v:$A6;o:$2F88),(v:$A2;o:$2FDC),(v:$87;o:$3069),(v:$9C;o:$30A4),(v:$5D;o:$31AA),
 (v:$9C;o:$31C9),(v:$15;o:$31F2),(v:$30;o:$3202),(v:$97;o:$3203),(v:$9F;o:$320A),(v:$9B;o:$3212),
 (v:$9B;o:$3213),(v:$5E;o:$3242),(v:$09;o:$3261),(v:$5C;o:$326A),(v:$4E;o:$3292),(v:$DC;o:$3388),
 (v:$57;o:$3497),(v:$77;o:$3523),(v:$D6;o:$3538),(v:$BF;o:$354A),(v:$C6;o:$361E),(v:$61;o:$3721),
 (v:$62;o:$3992),(v:$C2;o:$3AA5),(v:$88;o:$3AB2),(v:$40;o:$3ACD),(v:$74;o:$3E0E),(v:$61;o:$3E61),
 (v:$C3;o:$3FD3),(v:$70;o:$400D),(v:$67;o:$4064),(v:$3B;o:$40B2),(v:$3A;o:$40B3),(v:$1C;o:$4110),
 (v:$1D;o:$4190),(v:$0F;o:$41A3),(v:$0C;o:$41AA),(v:$3F;o:$41E3),(v:$75;o:$41E4),(v:$BE;o:$41E6),
 (v:$2F;o:$41EE),(v:$76;o:$41F4),(v:$4F;o:$4293),(v:$41;o:$42CD),(v:$35;o:$44A2),(v:$9F;o:$44AA),
 (v:$9B;o:$44B2),(v:$9B;o:$44B3),(v:$A5;o:$463C),(v:$14;o:$47D3),(v:$42;o:$48B0),(v:$99;o:$4910),
 (v:$6A;o:$4981),(v:$99;o:$4990),(v:$14;o:$49E5),(v:$16;o:$49F2),(v:$AC;o:$4A25),(v:$6B;o:$4A41),
 (v:$0B;o:$4A6A),(v:$0D;o:$4A6C),(v:$13;o:$4A91),(v:$6F;o:$4C2C),(v:$12;o:$4C4B),(v:$34;o:$4C62),
 (v:$9F;o:$4C6A),(v:$9B;o:$4C72),(v:$9B;o:$4C73),(v:$51;o:$4C74),(v:$71;o:$4D13),(v:$A6;o:$4D85),
 (v:$84;o:$4DC9),(v:$21;o:$4E92),(v:$37;o:$4EC2),(v:$9F;o:$4ECA),(v:$9B;o:$4ED2),(v:$9B;o:$4ED3),
 (v:$2B;o:$4F14),(v:$AF;o:$4FA1),(v:$96;o:$50B3),(v:$A1;o:$50C9),(v:$D4;o:$50FC),(v:$38;o:$5122),
 (v:$E5;o:$5198),(v:$A3;o:$51D4),(v:$8B;o:$51E2),(v:$82;o:$520F),(v:$F0;o:$521A),(v:$8E;o:$5245),
 (v:$69;o:$5297),(v:$95;o:$5305),(v:$81;o:$5625),(v:$DE;o:$569D),(v:$B2;o:$56C2),(v:$1A;o:$5983),
 (v:$A3;o:$5A04),(v:$E0;o:$5A4E),(v:$9A;o:$5C53),(v:$9A;o:$5C81),(v:$9C;o:$5CA4),(v:$B8;o:$5D5E),
 (v:$9C;o:$5DC9),(v:$97;o:$5E03),(v:$A4;o:$5E83),(v:$62;o:$5EDF),(v:$E1;o:$6003),(v:$66;o:$602C),
 (v:$65;o:$6033),(v:$2D;o:$6034),(v:$6E;o:$6053),(v:$02;o:$608C),(v:$28;o:$60A4),(v:$48;o:$6110),
 (v:$72;o:$6113),(v:$D9;o:$6142),(v:$4C;o:$6190),(v:$BA;o:$61A1),(v:$68;o:$61A6),(v:$6D;o:$61C1),
 (v:$26;o:$61C9),(v:$11;o:$6203),(v:$CB;o:$6231),(v:$2E;o:$6274),(v:$05;o:$6293),(v:$9E;o:$62CD),
 (v:$9E;o:$62ED),(v:$55;o:$6334),(v:$2C;o:$6434),(v:$03;o:$648C),(v:$27;o:$64A4),(v:$49;o:$6510),
 (v:$73;o:$6513),(v:$4D;o:$6590),(v:$25;o:$65C9),(v:$10;o:$6603),(v:$06;o:$6693),(v:$9E;o:$66CD),
 (v:$9E;o:$66ED),(v:$54;o:$6714),(v:$AB;o:$68C2),(v:$D7;o:$6A46),(v:$39;o:$6A93),(v:$EA;o:$6B3A),
 (v:$6F;o:$733C),(v:$A9;o:$73F5),(v:$67;o:$7833),(v:$6D;o:$7B65),(v:$6A;o:$7C8D),(v:$A7;o:$7D7A),
 (v:$69;o:$7E9D),(v:$C9;o:$7F58),(v:$B7;o:$7F79),(v:$A7;o:$8154),(v:$D1;o:$843F),(v:$77;o:$864A),
 (v:$62;o:$8976),(v:$F0;o:$8A4B),(v:$CE;o:$8C5C),(v:$02;o:$8D39),(v:$71;o:$8D4A),(v:$74;o:$92F2),
 (v:$76;o:$9704),(v:$EC;o:$9833),(v:$F0;o:$987A),(v:$AA;o:$990E),(v:$A9;o:$9998),(v:$11;o:$9B5A),
 (v:$B9;o:$9B88),(v:$AE;o:$9E9D),(v:$D5;o:$9F41),(v:$61;o:$9F52),(v:$03;o:$A146),(v:$A4;o:$A152),
 (v:$0D;o:$A224),(v:$B0;o:$A307),(v:$C1;o:$A3EE),(v:$BB;o:$A421),(v:$E7;o:$A7EE),(v:$65;o:$A934),
 (v:$B4;o:$A9FB),(v:$66;o:$AB24),(v:$AD;o:$ACD0),(v:$64;o:$AFC6),(v:$BE;o:$B2B3),(v:$BD;o:$B633),
 (v:$E3;o:$B64B),(v:$CF;o:$B904),(v:$AE;o:$B9DA),(v:$C5;o:$B9F0),(v:$0A;o:$BA05),(v:$DD;o:$BA64),
 (v:$E4;o:$BEEA),(v:$CC;o:$BFBD),(v:$C0;o:$C10A),(v:$73;o:$C257),(v:$75;o:$CA0E),(v:$6E;o:$CA5A),
 (v:$09;o:$CC30),(v:$C8;o:$CD5F),(v:$66;o:$CDE6),(v:$A1;o:$CE0D),(v:$C3;o:$CF8A),(v:$6C;o:$D040),
 (v:$E6;o:$D090),(v:$B1;o:$D0C2),(v:$6B;o:$D0CD),(v:$D8;o:$D417),(v:$04;o:$D720),(v:$6C;o:$D894),
 (v:$CF;o:$D91C),(v:$D8;o:$DB0C),(v:$CE;o:$DE1A),(v:$15;o:$DE7D),(v:$B3;o:$E073),(v:$E2;o:$E10B),
 (v:$E8;o:$E318),(v:$6A;o:$E3FC),(v:$0E;o:$E6E6),(v:$D0;o:$E767),(v:$B4;o:$E829),(v:$CD;o:$E97F),
 (v:$0C;o:$EA8C),(v:$C4;o:$EB60),(v:$C3;o:$EBA8),(v:$08;o:$EDEE),(v:$07;o:$EFC3),(v:$C7;o:$F129),
 (v:$72;o:$F166),(v:$CC;o:$F1FE),(v:$AA;o:$F353),(v:$64;o:$F5F1),(v:$A8;o:$F6D0),(v:$D0;o:$F6E5),
 (v:$C0;o:$F88C),(v:$B5;o:$FAC5),(v:$01;o:$FC2A),(v:$D2;o:$FCCE)
 );

begin

// szukanie indeksow dla MES
 y:=0;
 for x:=0 to length(mes)-1 do
  if ord(mes[x])>$7f then begin
   dec(mes[x],$80);
   imes[y]:=x;
   inc(y);
  end;


 for x:=0 to 255 do begin

  crc:=x shl 8;
  crc_:=crc;

  for y:=1 to 8 do begin
   crc := crc shl 1;
   crc_ := crc_ shr 1;

   if (crc and $00010000) > 0 then crc := crc xor $1021;
   if (crc_ and $80) > 0 then crc_ := crc_ xor $edb8832000;
  end;

  tcrc16[x] := integer(crc);
  tcrc32[x] := cardinal(crc_ shr 8);
 end;


 for IORes:=length(_hash)-1 downto 0 do hash[_hash[IORes].o] := _hash[IORes].v;


(*----------------------------------------------------------------------------*)
(*  przetwarzanie parametrow, inicjalizacja zmiennych                         *)
(*----------------------------------------------------------------------------*)

 plik_asm:='';

 if ParamCount<1 then Syntax;

 // odczyt parametrow
 for IORes:=1 to ParamCount do begin
  t:=ParamStr(IORes);

  if t<>'' then
  if not(t[1]='-') then begin              // w celu kompatybilnosci z Linuxami, Mac OS X

   if plik_asm<>'' then
    Syntax
   else
    plik_asm:=t

  end else begin

   _i:=2;
   while _i <= length(t) do begin

   case UpCase(t[_i]) of


    'C': case_used    := true;
    'P': full_name    := true;
    'S': silent       := true;
    'X': exclude_proc := true;
    'U': unused_label := true;
    'V': if UpCase(t[_i+1])='U' then begin inc(_i,2); VerifyProc := true end;


    'B': if UpCase(t[_i+1]) = 'C' then begin

          if length(t) <> 3 then Syntax;

	  BranchTest := true;
	  _i:=3;

         end else
         if t[_i+1]<>':' then
          Syntax
         else begin
          inc(_i,2);

          tmp:=get_dat(_i,t,' ',true);

          binary_file.adr := integer( oblicz_wartosc(tmp, t) );

          binary_file.use := true;
         end;

    'D': if t[_i+1]<>':' then Syntax else begin
          inc(_i,2);
          def_label:=get_lab(_i,t, true);

          if t[_i]<>'=' then
           nul.i:=1
          else begin
           inc(_i);
           nul.i:=integer( get_expres(_i,t,t, false) );
          end;

          s_lab(def_label,nul.i,bank,t,def_label[1]);
         end;

    'F': begin
          inc(_i);

	  if length(t) = 2 then

	    labFirstCol  := true

	  else

          case UpCase(t[_i]) of

           'V': if t[_i+1] <> ':' then
		  Syntax
		else begin
		  inc(_i, 2);
		  tmp:=get_dat(_i,t,' ',true);

		  fvalue := byte( oblicz_wartosc(tmp, t) );
                end;
           else
            Syntax
           end;

         end;

    'H': begin
          inc(_i);

          case UpCase(t[_i]) of
           'C': begin
                 list_hhh:=true;
                 if t[_i+1]=':' then plik_h:=nowy_plik(plik_h, _i);
                end;

           'M': begin
                 list_mmm:=true;
                 if t[_i+1]=':' then plik_hm:=nowy_plik(plik_hm, _i);
                end;
           else
            Syntax
           end;

         end;

    'I': if t[_i+1]<>':' then Syntax else begin
          name:=nowy_plik(name, _i);

          if name='' then Syntax else begin
           NormalizePath(name);
           t_pth[High(t_pth)]:=name;
           SetLength(t_pth, High(t_pth)+2);
          end;

         end;

    'L': begin
          opt:=opt or opt_L;
          if t[_i+1]=':' then plik_lst:=nowy_plik(plik_lst, _i);
         end;

    'M': begin
          inc(_i);

          case UpCase(t[_i]) of
           ':': begin
	         dec(_i);
                 list_mac:=true;
		 plik_mac:=nowy_plik(plik_mac, _i);
                end;

           'L': if t[_i+1] <> ':' then
		  Syntax
		else begin
		  inc(_i, 2);
		  tmp:=get_dat(_i,t,' ',true);
		  margin := integer( oblicz_wartosc(tmp, t) );

		  if margin < 32 then margin := 32;
		  if margin > 127 then margin := 128;
                end;
           else
            Syntax
           end;

         end;

    'O': if t[_i+1]<>':' then Syntax else plik_obj:=nowy_plik(plik_obj, _i);

    'T': begin
          list_lab:=true;
          if t[_i+1]=':' then plik_lab:=nowy_plik(plik_lab, _i);
         end;

   else
    Syntax;
   end;

   inc(_i);
   end;

  end;

 end;


 if (plik_asm='') or (GetFileName(plik_asm)='') then Syntax;

 NormalizePath(plik_asm);

 path:=GetFilePath(plik_asm);
 if path='' then begin GetDir(0,path); path:=path+PathDelim end;

 NormalizePath(path);

 name:=GetFileName(plik_asm);
 global_name:=name;

// sprawdzamy obecnosc pliku ASM
 plik_asm:=path+name;
 if not(TestFile(plik_asm)) then plik_asm := path + NewFileExt(name,'asm');

 if plik_lst = '' then plik_lst := path + NewFileExt(name,'lst');
 if plik_obj = '' then plik_obj := path + NewFileExt(name,'obx');
 if plik_lab = '' then plik_lab := path + NewFileExt(name,'lab');
 if plik_mac = '' then plik_mac := path + NewFileExt(name,'mac');
 if plik_h   = '' then plik_h   := path + NewFileExt(name,'h');
 if plik_hm  = '' then plik_hm  := path + NewFileExt(name,'hea');

 t:=load_mes(mads_version);

// if not(silent) then new_message(t);

 if list_lab then begin
  WriteAccessFile(plik_lab); AssignFile(lab,plik_lab); FileMode:=1; Rewrite(lab);
  writeln(lab,t);
  writeln(lab,load_mes(54+1));
 end;


 name:=GetFileName(plik_asm);
 _i:=1; name:=get_datUp(_i,name,'.',false);

 if list_mmm then begin
  WriteAccessFile(plik_hm); AssignFile(mmm,plik_hm); FileMode:=1; Rewrite(mmm);
 end;

 if list_hhh then begin
  WriteAccessFile(plik_h); AssignFile(hhh,plik_h); FileMode:=1; Rewrite(hhh);
  writeln(hhh,'#ifndef _'+name+'_ASM_H_');
  writeln(hhh,'#define _'+name+'_ASM_H_'+#13#10);
 end;

 WriteAccessFile(plik_obj); Assignfile(dst,plik_obj); FileMode:=1; Rewrite(dst,1);

 lst_header:=t;            // naglowek z informacja o wersji mads-a do pliku LST
end;


(*----------------------------------------------------------------------------*)
(*                         M A I N   P R O G R A M                            *)
(*----------------------------------------------------------------------------*)
begin

{$IFDEF WINDOWS}
 if GetFileType(GetStdHandle(STD_OUTPUT_HANDLE)) = 3 then begin
  Assign(Output, ''); Rewrite(Output);
 end;
{$ENDIF}

 SetLength(t_lin,1);
 SetLength(t_lab,1);
 SetLength(t_hea,1);
 SetLength(t_mac,1);
 SetLength(t_par,1);
 SetLength(t_loc,1);
 SetLength(t_prc,1);
 SetLength(t_pth,1);
 SetLength(t_wyw,1);
 SetLength(t_rel,1);
 SetLength(t_smb,1);
 SetLength(t_ext,1);
 SetLength(t_extn,1);
 SetLength(t_str,1);
 SetLength(t_pag,1);
 SetLength(t_end,1);
 SetLength(t_mad,1);
 SetLength(t_pub,1);
 SetLength(t_var,1);
 SetLength(t_seg,2);
 SetLength(t_skp,1);
 SetLength(t_sym,1);
 SetLength(t_usi,1);
 SetLength(t_els,1);
 SetLength(t_rep,1);
 SetLength(if_stos,1);

 SetLength(t_siz,2);

 SetLength(messages,1);

 SetLength(t_arr,2);                // predefiniowane parametry tablicy dla .PUT
 SetLength(t_arr[0].elm, 1);
 t_arr[0].adr:=0;
 t_arr[0].bnk:=0;
 t_arr[0].elm[0].cnt:=$FFFF+1;
 t_arr[0].elm[0].mul:=1;
 t_arr[0].siz:=1;

 array_idx:=1;

 pass:=1;

 binary_file.use:=false;
 plik_asm:='';
 status:=0;

(*----------------------------------------------------------------------------*)
(* tworzenie tablic 'TCRC16', 'TCRC32' oraz tablicy 'HASH', odczyt parametrow *)
(*----------------------------------------------------------------------------*)
 INITIALIZE;

 if binary_file.use then begin
  opt       := opt or opt_O;
  adres     := binary_file.adr;
  org       := true;
  first_org := false;
 end;

 optDefault := opt;
 atrDefault := atr;

 open_ok:=true;

 t:='';

 nul.l:=0;
 nul.i:=0;

 pass:=0;

 asem(plik_asm);

 over:=true;
 koniec(status);

end.
