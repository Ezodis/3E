/* Clicks-only output adapter for Kanata v1.12 wintercept.
 * Kanata emits generated keyboard strokes through device 1, even when a
 * device-specific Interception filter attaches the Clicks at another index.
 * Resolve that output to the currently attached Clicks on every send. All
 * other APIs and pass-through sends retain the upstream ABI and behavior.
 * No driver changes, hooks, settings, or keyboard-event logging occur here.
 */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

typedef void *Context;
typedef int (__cdecl *Predicate)(int);
#define API __declspec(dllexport)

static INIT_ONCE once = INIT_ONCE_STATIC_INIT;
static HMODULE upstream;
static int loaded;
static Context (__cdecl *p_create)(void);
static void (__cdecl *p_destroy)(Context);
static int (__cdecl *p_get_precedence)(Context,int);
static void (__cdecl *p_set_precedence)(Context,int,int);
static unsigned short (__cdecl *p_get_filter)(Context,int);
static void (__cdecl *p_set_filter)(Context,Predicate,unsigned short);
static int (__cdecl *p_wait)(Context);
static int (__cdecl *p_wait_timeout)(Context,unsigned long);
static int (__cdecl *p_send)(Context,int,const void *,unsigned int);
static int (__cdecl *p_receive)(Context,int,void *,unsigned int);
static unsigned int (__cdecl *p_hwid)(Context,int,void *,unsigned int);
static int (__cdecl *p_invalid)(int);
static int (__cdecl *p_keyboard)(int);
static int (__cdecl *p_mouse)(int);

static void start_accent_helper(const wchar_t *dll_path, DWORD base) {
    wchar_t exe[4096], parent[4096];
    const wchar_t name[]=L"ClicksAccents.exe";
    const wchar_t *leaf;
    DWORD j,n;
    HANDLE mutex;
    STARTUPINFOW si={0};
    PROCESS_INFORMATION pi={0};
    /* Only the live remapper launches the UI, inheriting its elevation. The
     * scheduled-task token may be medium integrity even with Highest set. */
    n=GetModuleFileNameW(NULL,parent,4096);
    if(!n || n>=4096)return;
    leaf=parent+n;while(leaf>parent && leaf[-1]!=L'\\')--leaf;
    if(lstrcmpiW(leaf,L"3EWindows.Keyboard.exe")!=0)return;
    mutex=OpenMutexW(SYNCHRONIZE,FALSE,L"Local\\3EWindows.ClicksAccents");
    if(mutex){CloseHandle(mutex);return;}
    if(base+sizeof(name)/sizeof(name[0])>4096)return;
    CopyMemory(exe,dll_path,base*sizeof(wchar_t));
    for(j=0;j<sizeof(name)/sizeof(name[0]);j++)exe[base+j]=name[j];
    if(GetFileAttributesW(exe)==INVALID_FILE_ATTRIBUTES)return;
    si.cb=sizeof(si);si.dwFlags=STARTF_USESHOWWINDOW;si.wShowWindow=SW_HIDE;
    if(CreateProcessW(exe,NULL,NULL,NULL,FALSE,CREATE_NO_WINDOW,NULL,NULL,&si,&pi)) {
        CloseHandle(pi.hThread);CloseHandle(pi.hProcess);
    }
}

static BOOL CALLBACK load_upstream(PINIT_ONCE init, PVOID arg, PVOID *result) {
    HMODULE self;
    wchar_t path[4096];
    const wchar_t name[] = L"interception_upstream.dll";
    DWORD n, base, j;
    (void)init; (void)arg; (void)result;
    if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                           GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                           (LPCWSTR)&load_upstream, &self)) return TRUE;
    n = GetModuleFileNameW(self, path, 4096);
    if (!n || n >= 4096) return TRUE;
    base = n;
    while (base && path[base-1] != L'\\') --base;
    if (!base || base + sizeof(name)/sizeof(name[0]) > 4096) return TRUE;
    for (j=0; j<sizeof(name)/sizeof(name[0]); ++j) path[base+j]=name[j];
    upstream = LoadLibraryExW(path, NULL, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR |
                                       LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!upstream) return TRUE;
#define RESOLVE(member, symbol) do { \
    *(FARPROC *)&member = GetProcAddress(upstream, symbol); \
    if (!member) return TRUE; \
} while (0)
    RESOLVE(p_create,"interception_create_context");
    RESOLVE(p_destroy,"interception_destroy_context");
    RESOLVE(p_get_precedence,"interception_get_precedence");
    RESOLVE(p_set_precedence,"interception_set_precedence");
    RESOLVE(p_get_filter,"interception_get_filter");
    RESOLVE(p_set_filter,"interception_set_filter");
    RESOLVE(p_wait,"interception_wait");
    RESOLVE(p_wait_timeout,"interception_wait_with_timeout");
    RESOLVE(p_send,"interception_send");
    RESOLVE(p_receive,"interception_receive");
    RESOLVE(p_hwid,"interception_get_hardware_id");
    RESOLVE(p_invalid,"interception_is_invalid");
    RESOLVE(p_keyboard,"interception_is_keyboard");
    RESOLVE(p_mouse,"interception_is_mouse");
#undef RESOLVE
    loaded = 1;
    start_accent_helper(path,base);
    return TRUE;
}

static int ready(void) {
    InitOnceExecuteOnce(&once,load_upstream,NULL,NULL);
    if (!loaded) SetLastError(ERROR_DLL_INIT_FAILED);
    return loaded;
}

static int clicks_at(Context c, int device) {
    static const wchar_t prefix[] =
        L"hid\\{00001812-0000-1000-8000-00805f9b34fb}_dev_vid&0107d7_pid&0000";
    wchar_t id[512] = {0};
    unsigned int bytes = p_hwid(c,device,id,sizeof(id));
    unsigned int i;
    if (bytes < sizeof(prefix) || bytes > sizeof(id)) return 0;
    for (i=0; prefix[i]; ++i) {
        wchar_t ch=id[i];
        if (ch >= L'A' && ch <= L'Z') ch += L'a'-L'A';
        if (ch != prefix[i]) return 0;
    }
    return id[i] == 0 || id[i] == L'_';
}

API Context __cdecl interception_create_context(void) { return ready()?p_create():NULL; }
API void __cdecl interception_destroy_context(Context c) { if(ready())p_destroy(c); }
API int __cdecl interception_get_precedence(Context c,int d) { return ready()?p_get_precedence(c,d):0; }
API void __cdecl interception_set_precedence(Context c,int d,int v) { if(ready())p_set_precedence(c,d,v); }
API unsigned short __cdecl interception_get_filter(Context c,int d) { return ready()?p_get_filter(c,d):0; }
API void __cdecl interception_set_filter(Context c,Predicate p,unsigned short f) { if(ready())p_set_filter(c,p,f); }
API int __cdecl interception_wait(Context c) { return ready()?p_wait(c):0; }
API int __cdecl interception_wait_with_timeout(Context c,unsigned long ms) { return ready()?p_wait_timeout(c,ms):0; }
API int __cdecl interception_receive(Context c,int d,void *s,unsigned int n) { return ready()?p_receive(c,d,s,n):0; }
API unsigned int __cdecl interception_get_hardware_id(Context c,int d,void *b,unsigned int n) { return ready()?p_hwid(c,d,b,n):0; }
API int __cdecl interception_is_invalid(int d) { return ready()?p_invalid(d):1; }
API int __cdecl interception_is_keyboard(int d) { return ready()?p_keyboard(d):0; }
API int __cdecl interception_is_mouse(int d) { return ready()?p_mouse(d):0; }

API int __cdecl interception_send(Context c,int device,const void *strokes,unsigned int count) {
    int target=0, d;
    struct KeyStroke { unsigned short code,state; unsigned int information; } *tagged;
    unsigned int i;
    int result;
    if (!ready()) return 0;
    if (device != 1) return p_send(c,device,strokes,count);
    /* Re-enumerate: Bluetooth reconnects and reboots can change the index. */
    for (d=1;d<=10;++d) {
        if (!clicks_at(c,d)) continue;
        if (target) { SetLastError(ERROR_DUP_NAME); return 0; }
        target=d;
    }
    if (!target) { SetLastError(ERROR_DEVICE_NOT_CONNECTED); return 0; }
    /* A private output tag lets the accent UI identify Clicks events without
     * guessing the source device or affecting keys from other keyboards. */
    if (!strokes || !count || count > 4096) { SetLastError(ERROR_INVALID_PARAMETER); return 0; }
    tagged = HeapAlloc(GetProcessHeap(),0,count*sizeof(*tagged));
    if (!tagged) { SetLastError(ERROR_NOT_ENOUGH_MEMORY); return 0; }
    CopyMemory(tagged,strokes,count*sizeof(*tagged));
    for (i=0;i<count;++i) tagged[i].information=0x3345434c;
    result=p_send(c,target,tagged,count);
    HeapFree(GetProcessHeap(),0,tagged);
    return result;
}
