// Read-only, deliberately limited Mach-O/ObjC metadata reader; never dlopen samples.
#import <Foundation/Foundation.h>
#import <mach-o/loader.h>
#import <mach-o/fat.h>
#import <libkern/OSByteOrder.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
static const uint8_t *b; static uint64_t size;
static struct section_64 sections[256]; static unsigned ns;
static uint64_t fixoff;
static int64_t sx(uint64_t x,unsigned bits){return ((int64_t)(x<<(64-bits)))>>(64-bits);}
static uint64_t page(uint64_t pc,uint32_t op){return (pc&~4095ull)+sx((((op>>5)&0x7ffff)<<2)|((op>>29)&3),21)*4096;}
static const char *bindname(uint64_t v){if(!(v>>63)||!fixoff)return NULL;uint32_t ordinal=v&0xffffff, count=r32(fixoff+16);if(ordinal>=count)return "<bad-import>";uint32_t format=r32(fixoff+20), base=r32(fixoff+8), syms=r32(fixoff+12),name=0;if(format==1||format==2)name=r32(fixoff+base+ordinal*(format==1?4:8))>>9;else if(format==3)name=r32(fixoff+base+ordinal*16+4);else return "<unsupported-import>";return (const char *)at(fixoff+syms+name,1);}
static const void *at(uint64_t o,uint64_t n) { if(o>size||n>size-o){fprintf(stderr,"out of bounds %llx\n",o);exit(2);}return b+o; }
static uint32_t r32(uint64_t o){uint32_t v;memcpy(&v,at(o,4),4);return v;}
static uint64_t r64(uint64_t o){uint64_t v;memcpy(&v,at(o,8),8);return v;}
static uint64_t off(uint64_t a){for(unsigned i=0;i<ns;i++){struct section_64 s=sections[i];if(a>=s.addr&&a-s.addr<s.size&&s.offset)return s.offset+a-s.addr;}fprintf(stderr,"unmapped VA %llx\n",a);exit(2);}
static uint64_t ptr(uint64_t a){uint64_t v=r64(off(a));if(v>>63){fprintf(stderr,"unsupported bind pointer at %llx\n",a);exit(2);}return (v&0xfffffffffull)|(((v>>36)&255ull)<<56);}
static const char *str(uint64_t a){if(!a)return "<null>";uint64_t o=off(a);const char *p=at(o,1);if(!memchr(p,0,size-o)){fprintf(stderr,"unterminated\n");exit(2);}return p;}
static void methods(uint64_t a,const char *cls,char sign){
 if(!a)return;uint64_t o=off(a);uint32_t flags=r32(o),cnt=r32(o+4),ents=flags&0xffff;ents&=~3u;
 if(cnt>100000||ents<12){fprintf(stderr,"unsupported method list\n");exit(2);}
 for(uint32_t i=0;i<cnt;i++){uint64_t e=a+8+(uint64_t)i*ents,imp,name,types;
 if(flags&0x80000000){name=e+(int32_t)r32(off(e));if(!(flags&0x40000000))name=ptr(name);types=e+4+(int32_t)r32(off(e+4));imp=e+8+(int32_t)r32(off(e+8));}
 else {name=ptr(e);types=ptr(e+8);imp=ptr(e+16);}
 printf("METHOD 0x%llx %c[%s %s] types=%s\n",imp,sign,cls,str(name),str(types));
 }
}
static void classinfo(uint64_t a,BOOL meta){uint64_t ro=ptr(a+32)&~7ull;const char *name=str(ptr(ro+24));printf("CLASS 0x%llx %s%s\n",a,meta?"meta ":"",name);methods(ptr(ro+32),name,meta?'+':'-');if(!meta)classinfo(ptr(a),YES);}
int main(int argc,char **argv){@autoreleasepool{
 if(argc!=2){fprintf(stderr,"usage: macho-read FILE (arm64 only)\n");return 1;}
 NSData *d=[NSData dataWithContentsOfFile:@(argv[1])];if(!d)return 1;b=d.bytes;size=d.length;
 if(r32(0)==FAT_CIGAM){uint32_t n=OSSwapBigToHostInt32(r32(4));BOOL found=NO;for(uint32_t i=0;i<n;i++){uint64_t o=8+(uint64_t)i*20;if(OSSwapBigToHostInt32(r32(o))==CPU_TYPE_ARM64 && (OSSwapBigToHostInt32(r32(o+4))&0xffffff)==0){uint64_t start=OSSwapBigToHostInt32(r32(o+8)),len=OSSwapBigToHostInt32(r32(o+12));at(start,len);b+=start;size=len;found=YES;break;}}if(!found)return 3;}
 if(r32(0)!=MH_MAGIC_64){fprintf(stderr,"unsupported Mach-O\n");return 3;}
 struct mach_header_64 h;memcpy(&h,at(0,sizeof(h)),sizeof(h));printf("HEADER cpu=0x%x subtype=0x%x type=%u ncmds=%u\n",h.cputype,h.cpusubtype,h.filetype,h.ncmds);
 uint64_t o=sizeof(h);for(unsigned i=0;i<h.ncmds;i++){struct load_command c;memcpy(&c,at(o,sizeof(c)),sizeof(c));if(c.cmdsize<8)return 2;at(o,c.cmdsize);
 if(c.cmd==LC_SEGMENT_64){struct segment_command_64 seg;memcpy(&seg,at(o,sizeof(seg)),sizeof(seg));for(unsigned j=0;j<seg.nsects;j++){if(ns>=256)return 2;struct section_64 s;memcpy(&s,at(o+sizeof(seg)+j*sizeof(s),sizeof(s)),sizeof(s));sections[ns++]=s;printf("SECTION %.16s,%.16s VA=0x%llx size=0x%llx offset=0x%x\n",s.segname,s.sectname,s.addr,s.size,s.offset);}}
 if(c.cmd==LC_LOAD_DYLIB||c.cmd==LC_LOAD_WEAK_DYLIB||c.cmd==LC_ID_DYLIB||c.cmd==LC_REEXPORT_DYLIB){uint32_t k=r32(o+8);if(k<c.cmdsize)printf("DYLIB cmd=0x%x %s\n",c.cmd,(const char *)at(o+k,c.cmdsize-k));}
 if(c.cmd==LC_RPATH){uint32_t k=r32(o+8);if(k<c.cmdsize)printf("RPATH %s\n",(const char *)at(o+k,c.cmdsize-k));}
 if(c.cmd==LC_BUILD_VERSION)printf("BUILD platform=%u minos=0x%x sdk=0x%x\n",r32(o+8),r32(o+12),r32(o+16));
 if(c.cmd==LC_ENCRYPTION_INFO_64)printf("ENCRYPT cryptid=%u\n",r32(o+16));
 if(c.cmd==LC_DYLD_CHAINED_FIXUPS){uint64_t fix=r32(o+8),starts=fix+r32(fix+4);uint32_t count=r32(starts);for(uint32_t j=0;j<count;j++){uint32_t so=r32(starts+4+j*4);if(!so)continue;uint32_t format=*(const uint16_t *)at(starts+so+6,2);printf("CHAINED_FORMAT %u\n",format);if(format!=2&&format!=6){fprintf(stderr,"unsupported pointer format\n");return 3;}}}
 o+=c.cmdsize;}
 for(unsigned i=0;i<ns;i++){struct section_64 s=sections[i];
 if(!strcmp(s.sectname,"__cstring")||!strcmp(s.sectname,"__objc_methname")||!strcmp(s.sectname,"__objc_classname")){uint64_t k=0;while(k<s.size){const char *v=str(s.addr+k);printf("STRING 0x%llx %s %s\n",s.addr+k,s.sectname,v);k+=strlen(v)+1;}}
 if(!strcmp(s.sectname,"__cfstring")){for(uint64_t k=0;k+32<=s.size;k+=32){uint64_t a=s.addr+k;printf("CFSTRING 0x%llx %s\n",a,str(ptr(a+16)));}}
 if(!strcmp(s.sectname,"__objc_selrefs")){for(uint64_t k=0;k+8<=s.size;k+=8)printf("SELREF 0x%llx %s\n",s.addr+k,str(ptr(s.addr+k)));}
 if(!strncmp(s.sectname,"__objc_classlist",16)){for(uint64_t k=0;k+8<=s.size;k+=8)classinfo(ptr(s.addr+k),NO);}
 if(!strncmp(s.sectname,"__init_offsets",16)){for(uint64_t k=0;k+4<=s.size;k+=4)printf("INIT 0x%x\n",r32(off(s.addr+k)));}
 if(!strcmp(s.sectname,"__mod_init_func")){for(uint64_t k=0;k+8<=s.size;k+=8)printf("INIT 0x%llx\n",ptr(s.addr+k));}
 }
 return 0;
}}
