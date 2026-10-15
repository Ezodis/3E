/* Offline harness: implements the Interception ABI without opening a driver or
 * sending any OS keyboard input. Only scripted events and an output log exist. */
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define API __declspec(dllexport)
typedef struct { unsigned short code,state; unsigned int information; } Stroke;
typedef struct { unsigned long ms; Stroke stroke; } Event;
static INIT_ONCE init=INIT_ONCE_STATIC_INIT;
static CRITICAL_SECTION lock;
static Event events[512];
static unsigned int count,index_event;
static unsigned long end_ms;
static ULONGLONG started;
static unsigned char hwid[1024];
static FILE *output;
static BOOL CALLBACK initialize(PINIT_ONCE once,PVOID arg,PVOID *ctx) {
    char path[32768]; FILE *input; unsigned int code,state; unsigned long time;
    (void)once;(void)arg;(void)ctx;InitializeCriticalSection(&lock);
    if(!GetEnvironmentVariableA("CLICKS_TEST_INPUT",path,sizeof(path)))ExitProcess(70);
    input=fopen(path,"r");if(!input)ExitProcess(71);
    while(count<512&&fscanf(input,"%lu %x %x",&time,&code,&state)==3){events[count].ms=time;events[count].stroke.code=(unsigned short)code;events[count].stroke.state=(unsigned short)state;count++;}
    fclose(input);
    if(!GetEnvironmentVariableA("CLICKS_TEST_OUTPUT",path,sizeof(path)))ExitProcess(72);
    output=fopen(path,"w");if(!output)ExitProcess(73);
    input=fopen("hwid.bin","rb");if(!input)ExitProcess(74);fread(hwid,1,sizeof(hwid),input);fclose(input);
    end_ms=count?events[count-1].ms+2000:2000;
    return TRUE;
}
static void ready(void){InitOnceExecuteOnce(&init,initialize,NULL,NULL);}
API void *interception_create_context(void){ready();return (void *)(ULONG_PTR)0x1234;}
API void interception_destroy_context(void *c){(void)c;}
API int interception_get_precedence(void *c,int d){(void)c;(void)d;return 0;}
API void interception_set_precedence(void *c,int d,int p){(void)c;(void)d;(void)p;}
API unsigned short interception_get_filter(void *c,int d){(void)c;(void)d;return 0xffff;}
API void interception_set_filter(void *c,int (*p)(int),unsigned short f){(void)c;(void)p;(void)f;}
API int interception_wait_with_timeout(void *c,unsigned long timeout){
    ULONGLONG now,deadline;(void)c;ready();if(!started)started=GetTickCount64();deadline=GetTickCount64()+timeout;
    for(;;){now=GetTickCount64()-started;
        if(now>=end_ms){EnterCriticalSection(&lock);fflush(output);LeaveCriticalSection(&lock);ExitProcess(0);}
        if(index_event<count&&now>=events[index_event].ms)return 8;
        if(timeout!=INFINITE&&GetTickCount64()>=deadline)return 0;
        Sleep(1);
    }
}
API int interception_wait(void *c){return interception_wait_with_timeout(c,INFINITE);}
API int interception_receive(void *c,int d,void *s,unsigned int n){(void)c;if(d!=8||!n||index_event>=count)return 0;memcpy(s,&events[index_event++].stroke,sizeof(Stroke));return 1;}
API int interception_send(void *c,int d,const void *data,unsigned int n){
    unsigned int i;const Stroke *s=(const Stroke *)data;(void)c;ready();
    EnterCriticalSection(&lock);
    for(i=0;i<n;i++)fprintf(output,"%llu %d %02X %02X\n",started?GetTickCount64()-started:0,d,s[i].code,s[i].state);
    fflush(output);LeaveCriticalSection(&lock);return (int)n;
}
API unsigned int interception_get_hardware_id(void *c,int d,void *b,unsigned int n){(void)c;ready();if(d!=8||n<sizeof(hwid))return 0;memcpy(b,hwid,sizeof(hwid));return sizeof(hwid);}
API int interception_is_invalid(int d){return d<1||d>20;}
API int interception_is_keyboard(int d){return d>=1&&d<=10;}
API int interception_is_mouse(int d){return d>=11&&d<=20;}
