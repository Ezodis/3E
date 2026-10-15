#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <string.h>
#define API __declspec(dllexport)
static unsigned int mask;
static int last_device, sends, precedence;
static unsigned short filter;
static unsigned int last_information;
API unsigned int test_information(void) { return last_information; }
static void *expected=(void *)(ULONG_PTR)0x1234;
API void test_devices(unsigned int value) { mask=value; last_device=0; sends=0; }
API int test_last(void) { return last_device; }
API int test_sends(void) { return sends; }
API void *interception_create_context(void) { return expected; }
API void interception_destroy_context(void *c) { (void)c; }
API int interception_get_precedence(void *c,int d) { (void)c;(void)d;return precedence; }
API void interception_set_precedence(void *c,int d,int p) { (void)c;(void)d;precedence=p; }
API unsigned short interception_get_filter(void *c,int d) { (void)c;(void)d;return filter; }
API void interception_set_filter(void *c,int (*p)(int),unsigned short f) { (void)c;if(p(5))filter=f; }
API int interception_wait(void *c) { (void)c;return 5; }
API int interception_wait_with_timeout(void *c,unsigned long ms) { (void)c;return ms==123?5:0; }
API int interception_send(void *c,int d,const void *s,unsigned int n) {
    if(c!=expected||!s)return 0;
    last_information=((const unsigned int *)s)[1];
    last_device=d;++sends;return (int)n;
}
API int interception_receive(void *c,int d,void *s,unsigned int n) { (void)c;(void)s;return d==5?(int)n:0; }
API unsigned int interception_get_hardware_id(void *c,int d,void *b,unsigned int n) {
    const wchar_t clicks[]=L"HID\\{00001812-0000-1000-8000-00805F9B34FB}_Dev_VID&0107d7_PID&0000_REV&0110\0HID_DEVICE\0";
    const wchar_t other[]=L"HID\\VID_258A&PID_1007\0";
    const wchar_t similar[]=L"HID\\{00001812-0000-1000-8000-00805F9B34FB}_Dev_VID&0107d7_PID&00001\0";
    const wchar_t *id; unsigned int bytes;
    if(c!=expected||d<1||d>10)return 0;
    if(mask&(1u<<d)){id=clicks;bytes=sizeof(clicks);}
    else if(d==1){id=(mask&0x80000000)?similar:other;bytes=(mask&0x80000000)?sizeof(similar):sizeof(other);}
    else return 0;
    if(n<bytes)return 0;memcpy(b,id,bytes);return bytes;
}
API int interception_is_invalid(int d) { return d<1||d>20; }
API int interception_is_keyboard(int d) { return d>=1&&d<=10; }
API int interception_is_mouse(int d) { return d>=11&&d<=20; }
