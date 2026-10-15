#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#define CHECK(x) do {if(!(x)){fprintf(stderr,"FAIL line %d: %s\n",__LINE__,#x);exit(1);}}while(0)
static int predicate(int d){return d==5;}
int main(void) {
    HMODULE dll=LoadLibraryW(L"interception.dll"), original;
    void *c;unsigned char stroke[20]={0};wchar_t ids[512]={0};
    void *(*create)(void);void (*destroy)(void *);
    int (*send)(void *,int,const void *,unsigned int);
    unsigned int (*hwid)(void *,int,void *,unsigned int);
    int (*getprecedence)(void *,int);void (*setprecedence)(void *,int,int);
    unsigned short (*getfilter)(void *,int);void (*setfilter)(void *,int (*)(int),unsigned short);
    int (*wait)(void *);int (*timeout)(void *,unsigned long);
    int (*receive)(void *,int,void *,unsigned int);
    int (*invalid)(int),(*keyboard)(int),(*mouse)(int);
    void (*devices)(unsigned int);int (*last)(void),(*sends)(void);
    unsigned int (*information)(void);
    CHECK(dll);
#define GET(var,sym) do {*(FARPROC *)&var=GetProcAddress(dll,sym);CHECK(var);}while(0)
    GET(create,"interception_create_context");GET(destroy,"interception_destroy_context");
    GET(send,"interception_send");GET(hwid,"interception_get_hardware_id");
    GET(getprecedence,"interception_get_precedence");GET(setprecedence,"interception_set_precedence");
    GET(getfilter,"interception_get_filter");GET(setfilter,"interception_set_filter");
    GET(wait,"interception_wait");GET(timeout,"interception_wait_with_timeout");
    GET(receive,"interception_receive");GET(invalid,"interception_is_invalid");
    GET(keyboard,"interception_is_keyboard");GET(mouse,"interception_is_mouse");
    c=create();CHECK(c==(void *)(ULONG_PTR)0x1234);
    original=GetModuleHandleW(L"interception_upstream.dll");CHECK(original);
    *(FARPROC *)&devices=GetProcAddress(original,"test_devices");
    *(FARPROC *)&last=GetProcAddress(original,"test_last");
    *(FARPROC *)&sends=GetProcAddress(original,"test_sends");CHECK(devices&&last&&sends);
    *(FARPROC *)&information=GetProcAddress(original,"test_information");CHECK(information);
    devices(1u<<5);CHECK(send(c,1,stroke,1)==1&&last()==5&&sends()==1);
    CHECK(information()==0x3345434c && ((unsigned int *)stroke)[1]==0);
    CHECK(hwid(c,5,ids,sizeof(ids))>0);
    devices(1u<<1);CHECK(send(c,1,stroke,2)==2&&last()==1);
    devices(1u<<8);CHECK(send(c,1,stroke,1)==1&&last()==8);
    devices(0);CHECK(send(c,1,stroke,1)==0&&sends()==0);
    devices(0x80000000);CHECK(send(c,1,stroke,1)==0&&sends()==0);
    devices((1u<<5)|(1u<<8));CHECK(send(c,1,stroke,1)==0&&sends()==0);
    devices(1u<<5);CHECK(send(c,5,stroke,1)==1&&last()==5);
    CHECK(information()==0);
    CHECK(send(c,11,stroke,1)==1&&last()==11);
    setprecedence(c,5,100);CHECK(getprecedence(c,5)==100);
    setfilter(c,predicate,0xffff);CHECK(getfilter(c,5)==0xffff);
    CHECK(wait(c)==5&&timeout(c,123)==5&&receive(c,5,stroke,1)==1);
    CHECK(invalid(0)&&!invalid(20)&&keyboard(1)&&!keyboard(11)&&mouse(11)&&!mouse(1));
    destroy(c);
    puts("PASS: all exports; slot 5/1/8 reconnect routing; absent and ambiguous devices; non-Clicks isolation; original-device pass-through.");
    return 0;
}
