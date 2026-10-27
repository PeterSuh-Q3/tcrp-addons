/* Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
 * Minimal persistent DRM/KMS text renderer for the DSM junior self-test.
 * It accepts one status record per line in a file and owns the display while
 * the junior environment is running. No fbdev or virtual console is needed.
 */
#define _GNU_SOURCE
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdint.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>
#include <drm.h>
#include <drm_mode.h>

#define U64(p) ((__u64)(uintptr_t)(p))
#define CONNECTED 1
#define MAX_DISKS 8
#define MAX_NICS 8
#define MAX_GPUS 4
#define MAX_DRM_CARDS 8
#define FIELD_LABEL_WIDTH 21

struct status {
    char ip[64], ping[48], port[24], disk_count[16], refresh[32];
    char cmdline[2048];
    char model[64], serial[64], mac[32], build[64], update[32], platform[96];
    char lkm_version[128], modules_version[128], module_type[128], loader_version[96];
    char cpu[160], threads[16], dmi[160], boot[16];
    char hba_count[16], pci_nic_count[16], gpu_count[16];
    char sata_count[16], nvme_count[16];
    char nics[MAX_NICS][192], gpus[MAX_GPUS][160], disks[MAX_DISKS][192];
    int nic_rows, gpu_rows, disk_rows;
};

struct display {
    int fd;
    unsigned int card_index;
    uint32_t connector;
    char connector_name[40];
    char connector_label[64];
    int connector_connected;
    uint32_t crtc;
    struct drm_mode_modeinfo mode;
    struct drm_mode_crtc original_crtc;
    int original_crtc_valid;
    int modeset_active;
    struct drm_mode_create_dumb dumb;
    struct drm_mode_fb_cmd fb;
    uint32_t *pixels;
    int dirtyfb_reported;
};

static volatile sig_atomic_t running = 1;
static void restore_display(struct display *d);

static int card_driver_name(unsigned int card, char *name, size_t name_size)
{
    char path[96], target[256];
    ssize_t length;
    snprintf(path, sizeof(path), "/sys/class/drm/card%u/device/driver", card);
    length = readlink(path, target, sizeof(target) - 1);
    if (length < 0)
        return -1;
    target[length] = '\0';
    const char *base = strrchr(target, '/');
    base = base ? base + 1 : target;
    if (!*base || strlen(base) >= name_size) {
        errno = ENAMETOOLONG;
        return -1;
    }
    memcpy(name, base, strlen(base) + 1);
    return 0;
}

static void stop_display(int signal_number)
{
    (void)signal_number;
    running = 0;
}

static const uint8_t *glyph(char c)
{
    static const uint8_t blank[7] = {0};
    static const uint8_t unknown[7] = {31,17,21,21,21,17,31};
#define G(ch,a,b,c,d,e,f,g) case ch: { static const uint8_t v[7]={a,b,c,d,e,f,g}; return v; }
    c = (char)toupper((unsigned char)c);
    switch (c) {
    G('A',14,17,17,31,17,17,17) G('B',30,17,17,30,17,17,30)
    G('C',14,17,16,16,16,17,14) G('D',30,17,17,17,17,17,30)
    G('E',31,16,16,30,16,16,31) G('F',31,16,16,30,16,16,16)
    G('G',14,17,16,23,17,17,15) G('H',17,17,17,31,17,17,17)
    G('I',14,4,4,4,4,4,14) G('J',7,2,2,2,18,18,12)
    G('K',17,18,20,24,20,18,17) G('L',16,16,16,16,16,16,31)
    G('M',17,27,21,21,17,17,17) G('N',17,25,25,21,19,19,17)
    G('O',14,17,17,17,17,17,14) G('P',30,17,17,30,16,16,16)
    G('Q',14,17,17,17,21,18,13) G('R',30,17,17,30,20,18,17)
    G('S',15,16,16,14,1,1,30) G('T',31,4,4,4,4,4,4)
    G('U',17,17,17,17,17,17,14) G('V',17,17,17,17,17,10,4)
    G('W',17,17,17,21,21,21,10) G('X',17,17,10,4,10,17,17)
    G('Y',17,17,10,4,4,4,4) G('Z',31,1,2,4,8,16,31)
    G('0',14,17,19,21,25,17,14) G('1',4,12,4,4,4,4,14)
    G('2',14,17,1,2,4,8,31) G('3',30,1,1,14,1,1,30)
    G('4',2,6,10,18,31,2,2) G('5',31,16,16,30,1,1,30)
    G('6',14,16,16,30,17,17,14) G('7',31,1,2,4,8,8,8)
    G('8',14,17,17,14,17,17,14) G('9',14,17,17,15,1,1,14)
    G(':',0,4,4,0,4,4,0) G('.',0,0,0,0,0,12,12)
    G(',',0,0,0,0,0,4,8) G('=',0,31,0,31,0,0,0)
    G('+',0,4,4,31,4,4,0) G('[',14,8,8,8,8,8,14)
    G(']',14,2,2,2,2,2,14)
    G('/',1,2,2,4,8,8,16) G('-',0,0,0,31,0,0,0)
    G('_',0,0,0,0,0,0,31) G('(',2,4,8,8,8,4,2)
    G(')',8,4,2,2,2,4,8) G(' ',0,0,0,0,0,0,0)
    default: return isprint((unsigned char)c) ? unknown : blank;
    }
#undef G
}

static void pixel(struct display *d, int x, int y, uint32_t color)
{
    if (x >= 0 && y >= 0 && x < d->mode.hdisplay && y < d->mode.vdisplay)
        d->pixels[(size_t)y * (d->dumb.pitch / 4) + x] = color;
}

static void text(struct display *d, int x, int y, int scale,
                 const char *s, uint32_t color)
{
    for (; *s; s++, x += 6 * scale) {
        const uint8_t *rows = glyph(*s);
        for (int gy = 0; gy < 7; gy++)
            for (int gx = 0; gx < 5; gx++)
                if (rows[gy] & (1u << (4 - gx)))
                    for (int sy = 0; sy < scale; sy++)
                        for (int sx = 0; sx < scale; sx++)
                            pixel(d, x + gx * scale + sx,
                                  y + gy * scale + sy, color);
    }
}

static int ioctl_ok(int fd, unsigned long op, void *arg)
{
    int rc;
    do { rc = ioctl(fd, op, arg); } while (rc < 0 && errno == EINTR);
    return rc;
}

static int get_connector(int fd, uint32_t id, struct drm_mode_get_connector *c,
                         struct drm_mode_modeinfo **modes_out,
                         uint32_t **encoders_out)
{
    memset(c, 0, sizeof(*c));
    c->connector_id = id;
    if (ioctl_ok(fd, DRM_IOCTL_MODE_GETCONNECTOR, c) < 0)
        return -1;
    struct drm_mode_modeinfo *modes = calloc(c->count_modes ? c->count_modes : 1,
                                               sizeof(*modes));
    uint32_t *encoders = calloc(c->count_encoders ? c->count_encoders : 1, 4);
    uint32_t *props = calloc(c->count_props ? c->count_props : 1, 4);
    uint64_t *values = calloc(c->count_props ? c->count_props : 1, 8);
    if (!modes || !encoders || !props || !values) {
        free(modes); free(encoders); free(props); free(values);
        errno = ENOMEM;
        return -1;
    }
    c->modes_ptr = U64(modes);
    c->encoders_ptr = U64(encoders);
    c->props_ptr = U64(props);
    c->prop_values_ptr = U64(values);
    if (ioctl_ok(fd, DRM_IOCTL_MODE_GETCONNECTOR, c) < 0) {
        free(modes); free(encoders); free(props); free(values);
        return -1;
    }
    free(props); free(values);
    *modes_out = modes;
    *encoders_out = encoders;
    return 0;
}

static const char *connector_type_name(uint32_t type)
{
    switch (type) {
    case DRM_MODE_CONNECTOR_VGA: return "VGA";
    case DRM_MODE_CONNECTOR_DVII: return "DVI-I";
    case DRM_MODE_CONNECTOR_DVID: return "DVI-D";
    case DRM_MODE_CONNECTOR_DVIA: return "DVI-A";
    case DRM_MODE_CONNECTOR_Composite: return "COMPOSITE";
    case DRM_MODE_CONNECTOR_SVIDEO: return "SVIDEO";
    case DRM_MODE_CONNECTOR_LVDS: return "LVDS";
    case DRM_MODE_CONNECTOR_Component: return "COMPONENT";
    case DRM_MODE_CONNECTOR_9PinDIN: return "DIN";
    case DRM_MODE_CONNECTOR_DisplayPort: return "DP";
    case DRM_MODE_CONNECTOR_HDMIA: return "HDMI-A";
    case DRM_MODE_CONNECTOR_HDMIB: return "HDMI-B";
    case DRM_MODE_CONNECTOR_TV: return "TV";
    case DRM_MODE_CONNECTOR_eDP: return "EDP";
    case DRM_MODE_CONNECTOR_VIRTUAL: return "VIRTUAL";
    case DRM_MODE_CONNECTOR_DSI: return "DSI";
    default: return "UNKNOWN";
    }
}

static void set_connector_name(char *dst, size_t size, uint32_t type,
                               uint32_t type_id)
{
    snprintf(dst,size,"%s-%u",connector_type_name(type),type_id);
}

static int i915_downstream_type(const char *debugfs_dir,
                                const char *connector_name,
                                char *type, size_t type_size)
{
    char path[256], line[512], card_name[128], connector_tag[64];
    snprintf(path,sizeof(path),"%s/name",debugfs_dir);
    FILE *f=fopen(path,"r");
    if (!f)
        return 0;
    int is_i915=fgets(card_name,sizeof(card_name),f) &&
        !strncmp(card_name,"i915 ",5);
    fclose(f);
    if (!is_i915 || strncmp(connector_name,"DP-",3))
        return 0;

    snprintf(path,sizeof(path),"%s/i915_display_info",debugfs_dir);
    f=fopen(path,"r");
    if (!f)
        return 0;
    snprintf(connector_tag,sizeof(connector_tag),":%s]",connector_name);
    int matched=0, branch_present=0, found=0;
    while (fgets(line,sizeof(line),f)) {
        if (strstr(line,"[CONNECTOR:")) {
            matched=strstr(line,connector_tag)!=NULL;
            branch_present=0;
            continue;
        }
        if (!matched)
            continue;
        if (strstr(line,"DP branch device present:")) {
            branch_present=strstr(line,"yes")!=NULL;
            continue;
        }
        if (branch_present && strstr(line,"Type:")) {
            char downstream[32];
            if (sscanf(line," Type: %31s",downstream)==1) {
                snprintf(type,type_size,"%s",downstream);
                found=1;
            }
            break;
        }
    }
    fclose(f);
    return found;
}

static void set_connector_label(struct display *d)
{
    snprintf(d->connector_label,sizeof(d->connector_label),"%s",d->connector_name);
    char debugfs_dir[128], downstream[32];
    snprintf(debugfs_dir,sizeof(debugfs_dir),"/sys/kernel/debug/dri/%u",
             d->card_index);
    if (i915_downstream_type(debugfs_dir,d->connector_name,
                             downstream,sizeof(downstream)))
        snprintf(d->connector_label,sizeof(d->connector_label),"%s (%s downstream)",
                 d->connector_name,downstream);
}

static int setup_display(struct display *d)
{
    struct drm_mode_card_res r = {0};
    if (ioctl_ok(d->fd, DRM_IOCTL_MODE_GETRESOURCES, &r) < 0)
        return -1;
    uint32_t *crtcs = calloc(r.count_crtcs ? r.count_crtcs : 1, 4);
    uint32_t *connectors = calloc(r.count_connectors ? r.count_connectors : 1, 4);
    uint32_t *fbs = calloc(r.count_fbs ? r.count_fbs : 1, 4);
    uint32_t *encs = calloc(r.count_encoders ? r.count_encoders : 1, 4);
    if (!crtcs || !connectors || !fbs || !encs) {
        errno = ENOMEM;
        goto fail;
    }
    r.crtc_id_ptr=U64(crtcs); r.connector_id_ptr=U64(connectors);
    r.fb_id_ptr=U64(fbs); r.encoder_id_ptr=U64(encs);
    if (ioctl_ok(d->fd, DRM_IOCTL_MODE_GETRESOURCES, &r) < 0)
        goto fail;

    uint32_t selected_crtc=0, selected_conn=0;
    uint32_t selected_type=DRM_MODE_CONNECTOR_Unknown, selected_type_id=0;
    int selected_connected=0;
    struct drm_mode_modeinfo selected_mode={0};
    int best_score=-1;
    for (uint32_t i=0; i<r.count_connectors; i++) {
        struct drm_mode_get_connector c;
        struct drm_mode_modeinfo *modes=NULL;
        uint32_t *encoder_ids=NULL;
        if (get_connector(d->fd, connectors[i], &c, &modes, &encoder_ids) < 0)
            continue;
        if (c.connection != CONNECTED || !c.count_modes ||
            c.connector_type == DRM_MODE_CONNECTOR_WRITEBACK) {
            free(modes); free(encoder_ids); continue;
        }
        uint32_t crtc_id=0;
        struct drm_mode_modeinfo candidate_mode={0};
        int active=0;
        if (c.encoder_id) {
            struct drm_mode_get_encoder e={.encoder_id=c.encoder_id};
            if (ioctl_ok(d->fd, DRM_IOCTL_MODE_GETENCODER, &e) == 0 && e.crtc_id) {
                crtc_id=e.crtc_id;
                struct drm_mode_crtc state={.crtc_id=crtc_id};
                if (ioctl_ok(d->fd, DRM_IOCTL_MODE_GETCRTC, &state) == 0 &&
                    state.mode_valid) {
                    active=1;
                    for (uint32_t j=0; j<c.count_modes; j++)
                        if (modes[j].hdisplay == state.mode.hdisplay &&
                            modes[j].vdisplay == state.mode.vdisplay &&
                            modes[j].clock == state.mode.clock) {
                            candidate_mode=modes[j];
                            break;
                        }
                    if (!candidate_mode.hdisplay)
                        candidate_mode=state.mode;
                }
            }
        }
        if (!crtc_id) {
            for (uint32_t j=0; j<c.count_encoders && !crtc_id; j++) {
                struct drm_mode_get_encoder e={.encoder_id=encoder_ids[j]};
                if (ioctl_ok(d->fd, DRM_IOCTL_MODE_GETENCODER, &e) < 0)
                    continue;
                for (uint32_t k=0; k<r.count_crtcs; k++)
                    if (e.possible_crtcs & (1u << k)) { crtc_id=crtcs[k]; break; }
            }
        }
        if (crtc_id && !active) {
            int preferred=-1;
            for (uint32_t j=0; j<c.count_modes; j++) {
                if (modes[j].type & DRM_MODE_TYPE_PREFERRED) { preferred=(int)j; break; }
                if (preferred < 0 || (uint64_t)modes[j].hdisplay*modes[j].vdisplay >
                    (uint64_t)modes[preferred].hdisplay*modes[preferred].vdisplay)
                    preferred=(int)j;
            }
            if (preferred >= 0) candidate_mode=modes[preferred];
        }
        int score = active ? 1000000 : 0;
        if (candidate_mode.hdisplay && candidate_mode.vdisplay)
            score += (int)((uint64_t)candidate_mode.hdisplay * candidate_mode.vdisplay / 1000);
        if (crtc_id && candidate_mode.hdisplay && score > best_score) {
            best_score=score; selected_crtc=crtc_id;
            selected_conn=connectors[i];
            selected_type=c.connector_type;
            selected_type_id=c.connector_type_id;
            selected_connected=c.connection == CONNECTED;
            selected_mode=candidate_mode;
        }
        free(modes); free(encoder_ids);
    }
    free(crtcs); free(connectors); free(fbs); free(encs);
    if (!selected_conn || !selected_crtc || !selected_mode.hdisplay) {
        errno = ENODEV;
        return -1;
    }
    d->connector=selected_conn;
    set_connector_name(d->connector_name,sizeof(d->connector_name),
                       selected_type,selected_type_id);
    set_connector_label(d);
    d->connector_connected=selected_connected;
    d->crtc=selected_crtc; d->mode=selected_mode;
    d->original_crtc=(struct drm_mode_crtc){.crtc_id=d->crtc};
    if (ioctl_ok(d->fd, DRM_IOCTL_MODE_GETCRTC, &d->original_crtc) < 0)
        return -1;
    d->original_crtc_valid=1;
    d->dumb=(struct drm_mode_create_dumb){
        .width=d->mode.hdisplay, .height=d->mode.vdisplay, .bpp=32
    };
    if (ioctl_ok(d->fd, DRM_IOCTL_MODE_CREATE_DUMB, &d->dumb) < 0)
        return -1;
    struct drm_mode_map_dumb map={.handle=d->dumb.handle};
    if (ioctl_ok(d->fd, DRM_IOCTL_MODE_MAP_DUMB, &map) < 0)
        return -1;
    void *map_addr=mmap(NULL, d->dumb.size, PROT_READ|PROT_WRITE,
                        MAP_SHARED, d->fd, map.offset);
    if (map_addr == MAP_FAILED)
        return -1;
    d->pixels=map_addr;
    d->fb=(struct drm_mode_fb_cmd){
        .width=d->mode.hdisplay, .height=d->mode.vdisplay,
        .pitch=d->dumb.pitch, .bpp=32, .depth=24, .handle=d->dumb.handle
    };
    if (ioctl_ok(d->fd, DRM_IOCTL_MODE_ADDFB, &d->fb) < 0)
        return -1;
    struct drm_mode_crtc set={0};
    set.crtc_id=d->crtc; set.fb_id=d->fb.fb_id;
    set.set_connectors_ptr=U64(&d->connector); set.count_connectors=1;
    set.mode=d->mode; set.mode_valid=1;
    if (ioctl_ok(d->fd, DRM_IOCTL_MODE_SETCRTC, &set) < 0)
        return -1;
    d->modeset_active=1;
    fprintf(stderr, "KMS display active: connector=%u name=%s status=%s mode=%s %ux%u\n",
            d->connector, d->connector_label,
            d->connector_connected?"connected":"disconnected",
            d->mode.name, d->mode.hdisplay, d->mode.vdisplay);
    return 0;
fail:
    free(crtcs); free(connectors); free(fbs); free(encs);
    return -1;
}

static void draw_line(struct display *d, int *y, int scale,
                      int line_step, uint32_t color, const char *fmt, ...)
{
    char buf[256];
    va_list ap; va_start(ap,fmt); vsnprintf(buf,sizeof(buf),fmt,ap); va_end(ap);
    text(d,18*scale,*y,scale,buf,color);
    *y+=line_step;
}

static int draw_field(struct display *d, int x, int y, int scale,
                      const char *label, const char *value,
                      uint32_t label_color, uint32_t value_color)
{
    const char *colon=strchr(label,':');
    if (colon) {
        size_t prefix_len=(size_t)(colon-label);
        while (prefix_len>0 && label[prefix_len-1]==' ') prefix_len--;
        if (prefix_len<=FIELD_LABEL_WIDTH) {
            char prefix[FIELD_LABEL_WIDTH+1];
            memcpy(prefix,label,prefix_len);
            prefix[prefix_len]='\0';
            text(d,x,y,scale,prefix,label_color);
            int colon_x=x+FIELD_LABEL_WIDTH*6*scale;
            text(d,colon_x,y,scale,":",label_color);
            int value_x=colon_x+12*scale;
            text(d,value_x,y,scale,value,value_color);
            return value_x+(int)strlen(value)*6*scale;
        }
    }
    text(d,x,y,scale,label,label_color);
    x+=(int)strlen(label)*6*scale;
    text(d,x,y,scale,value,value_color);
    x+=((int)strlen(value)+2)*6*scale;
    return x;
}

static void draw_field_line(struct display *d, int x, int *y, int scale,
                            int line_step,
                            const char *label, const char *value,
                            uint32_t label_color, uint32_t value_color)
{
    (void)draw_field(d,x,*y,scale,label,value,label_color,value_color);
    *y+=line_step;
}

static int cmdline_wrapped_rows(int width, int scale, const char *value)
{
    int max_chars=(width-36*scale)/(6*scale);
    int rows=0;

    if (max_chars<1) return 0;
    if (max_chars>255) max_chars=255;
    while (*value) {
        while (*value==' ') value++;
        if (!*value) break;
        size_t length=strlen(value);
        size_t take=length<(size_t)max_chars?length:(size_t)max_chars;
        if (take<length) {
            size_t split=take;
            while (split>0 && value[split]!=' ') split--;
            if (split>0) take=split;
        }
        value+=take;
        rows++;
    }
    return rows;
}

static void draw_cmdline(struct display *d, int *y, int scale, int line_step,
                         int margin, const char *value)
{
    const uint32_t cyan=0xff66d9ef, white=0xffeeeeee;
    int max_chars=(d->mode.hdisplay-36*scale)/(6*scale);
    char line[256];
    if (max_chars<1) return;
    if (max_chars>(int)sizeof(line)-1) max_chars=(int)sizeof(line)-1;
    draw_field_line(d,margin,y,scale,line_step,"CMDLINE : ","",cyan,cyan);
    while (*value) {
        while (*value==' ') value++;
        if (!*value || *y+7*scale>=d->mode.vdisplay) break;
        size_t length=strlen(value);
        size_t take=length<(size_t)max_chars?length:(size_t)max_chars;
        if (take<length) {
            size_t split=take;
            while (split>0 && value[split]!=' ') split--;
            if (split>0) take=split;
        }
        memcpy(line,value,take);
        line[take]=0;
        draw_line(d,y,scale,line_step,white,"%s",line);
        value+=take;
    }
}

static int render_fits(const struct display *d, const struct status *s,
                       int scale, int line_step, int cmdline_scale,
                       int cmdline_step)
{
    int before_cmdline=24+s->gpu_rows+s->nic_rows;
    int after_cmdline=7+s->disk_rows;
    int cmdline_rows=1+cmdline_wrapped_rows(d->mode.hdisplay,cmdline_scale,
                                             s->cmdline);
    if (d->connector_name[0]) before_cmdline+=3;
    int top=(scale==2 && d->mode.hdisplay<1500)?9*scale:14*scale;
    int required=top+line_step*before_cmdline+
        cmdline_step*cmdline_rows+(line_step+1)/2+
        line_step*(after_cmdline-1)+7*scale;
    return required<=d->mode.vdisplay;
}

static void render(struct display *d, const struct status *s)
{
    const uint32_t bg=0xff000000, white=0xffeeeeee, muted=0xffa8a8a8;
    const uint32_t green=0xff58e39b, cyan=0xff66d9ef, red=0xffff7777;
    const uint32_t amber=0xffffc857, yellow=0xffffe66d;
    const uint32_t light_pink=0xffffb6c1;
    int scale=(d->mode.hdisplay>=1500 ||
               (d->mode.hdisplay>=960 && d->mode.vdisplay>=700))?2:1;
    int line_step=(scale==2 && d->mode.hdisplay<1500)?17:10*scale;
    int cmdline_scale=(scale==2 && d->mode.hdisplay<1500)?1:scale;
    int cmdline_step=10*cmdline_scale;
    if (!render_fits(d,s,scale,line_step,cmdline_scale,cmdline_step)) {
        scale=1;
        line_step=10;
        cmdline_scale=1;
        cmdline_step=10;
    }
    int compact_low_mode=(scale==2 && d->mode.hdisplay<1500);
    int margin=compact_low_mode?8*scale:10*scale;
    int y=margin+(compact_low_mode?1:4)*scale;
    size_t n=(size_t)(d->dumb.pitch/4)*d->mode.vdisplay;
    for (size_t i=0; i<n; i++) d->pixels[i]=bg;
    int step=line_step;
    static int last_logged_scale=0;
    if (last_logged_scale!=scale) {
        fprintf(stderr,"KMS text scale: %dx mode=%ux%u line-step=%d\n",
                scale,d->mode.hdisplay,d->mode.vdisplay,line_step);
        last_logged_scale=scale;
    }

    draw_line(d,&y,scale,line_step,light_pink,"##### TCRP MSHELL LOADER #####");
    y+=step;
    draw_field_line(d,margin,&y,scale,line_step,"MODEL : ",s->model,white,green);
    draw_field_line(d,margin,&y,scale,line_step,"SERIAL : ",s->serial,white,green);
    draw_field_line(d,margin,&y,scale,line_step,"MAC : ",s->mac,white,green);
    draw_field_line(d,margin,&y,scale,line_step,"BUILD : ",s->build,white,green);
    draw_field_line(d,margin,&y,scale,line_step,"UPDATE : ",s->update,white,green);
    draw_field_line(d,margin,&y,scale,line_step,"LKM : ",s->lkm_version,white,green);
    draw_field_line(d,margin,&y,scale,line_step,"tcrp-modules : ",s->modules_version,white,green);
    draw_field_line(d,margin,&y,scale,line_step,"Module Type : ",s->module_type,white,green);
    draw_field_line(d,margin,&y,scale,line_step,"Loader version : ",s->loader_version,white,green);
    draw_field_line(d,margin,&y,scale,line_step,"PLATFORM : ",s->platform,white,green);

    for (int i=0;i<s->gpu_rows;i++) {
        draw_field_line(d,margin,&y,scale,line_step,"GPU : ",s->gpus[i],white,green);
    }
    if (d->connector_name[0]) {
        draw_field_line(d,margin,&y,scale,line_step,"KMS Port : ",d->connector_label,white,green);
        draw_field_line(d,margin,&y,scale,line_step,"KMS Status : ",
                        d->connector_connected?"CONNECTED":"DISCONNECTED",white,
                        d->connector_connected?green:red);
        char resolution[32];
        snprintf(resolution,sizeof(resolution),"%ux%u",
                 d->mode.hdisplay,d->mode.vdisplay);
        draw_field_line(d,margin,&y,scale,line_step,"KMS Resolution : ",
                        resolution,white,white);
    }

    draw_field_line(d,margin,&y,scale,line_step,"CPU : ",s->cpu,white,0xffa0a0ff);
    draw_field_line(d,margin,&y,scale,line_step,"THREADS : ",s->threads,white,0xffa0a0ff);
    draw_field_line(d,margin,&y,scale,line_step,"DMI : ",s->dmi,white,yellow);

    draw_field_line(d,margin,&y,scale,line_step,"SAS/RAID HBAs Count : ",s->hba_count,white,red);
    draw_field_line(d,margin,&y,scale,line_step,"NICs Count : ",s->pci_nic_count,white,red);
    draw_field_line(d,margin,&y,scale,line_step,"GPU Count : ",s->gpu_count,white,red);
    draw_field_line(d,margin,&y,scale,line_step,"SAS/SATA Disks Count : ",s->sata_count,white,red);
    draw_field_line(d,margin,&y,scale,line_step,"NVMe Disks Count : ",s->nvme_count,white,red);

    draw_line(d,&y,scale,line_step,green,"System is running in %s boot mode",s->boot);

    for (int i=0;i<s->nic_rows;i++) {
        draw_field_line(d,margin,&y,scale,line_step,"Network : ",s->nics[i],white,green);
    }
    draw_cmdline(d,&y,cmdline_scale,cmdline_step,margin,s->cmdline);

    /* Keep the original self-test checks together at the bottom. */
    y+=step/2;
    draw_line(d,&y,scale,line_step,cyan,"JUNIOR REALTIME HELPER");
    draw_field_line(d,margin,&y,scale,line_step,"Current IP : ",s->ip,white,
                    !strcmp(s->ip,"WAITING")?amber:green);
    uint32_t ping_color=!strncmp(s->ping,"REPLY",5)?green:
        (!strcmp(s->ping,"WAITING")||!strcmp(s->ping,"UNAVAILABLE")?amber:red);
    draw_field_line(d,margin,&y,scale,line_step,"Gateway Ping : ",s->ping,white,ping_color);
    draw_field_line(d,margin,&y,scale,line_step,"DSM TCP/5000 : ",s->port,white,
                    !strcmp(s->port,"READY")?green:
                    (!strcmp(s->port,"WAITING")?amber:red));
    draw_field_line(d,margin,&y,scale,line_step,"Recognized Disks : ",s->disk_count,white,green);
    draw_line(d,&y,scale,line_step,muted,"DEVICE  SIZE  MODEL");
    for (int i=0;i<s->disk_rows;i++)
        draw_line(d,&y,scale,line_step,white,"%s",s->disks[i]);
    char refresh[64];
    snprintf(refresh,sizeof(refresh),"%s (2s interval)",s->refresh);
    draw_field_line(d,margin,&y,scale,line_step,"DISPLAY REFRESH : ",
                    refresh,cyan,cyan);
    __sync_synchronize();
    (void)msync((void *)d->pixels,d->dumb.size,MS_SYNC);
    struct drm_mode_fb_dirty_cmd dirty={.fb_id=d->fb.fb_id};
    if (ioctl_ok(d->fd,DRM_IOCTL_MODE_DIRTYFB,&dirty)<0) {
        if (!d->dirtyfb_reported) {
            fprintf(stderr,"KMS framebuffer refresh notification failed: %s\n",
                    strerror(errno));
            d->dirtyfb_reported=1;
        }
    } else if (!d->dirtyfb_reported) {
        fprintf(stderr,"KMS framebuffer refresh notification active\n");
        d->dirtyfb_reported=1;
    }
}

static int load_status(const char *path, char *buf, size_t size)
{
    FILE *f=fopen(path,"r");
    if (!f) return -1;
    size_t n=fread(buf,1,size-1,f);
    fclose(f);
    if (!n) return -1;
    buf[n]=0;
    return 0;
}

static void put(char *dst,size_t size,const char *src)
{
    snprintf(dst,size,"%s",src?src:"");
}

static int parse_status(char *data,struct status *s)
{
    memset(s,0,sizeof(*s));
    put(s->ip,sizeof(s->ip),"WAITING"); put(s->port,sizeof(s->port),"WAITING");
    char *save=NULL;
    for (char *line=strtok_r(data,"\n",&save);line;line=strtok_r(NULL,"\n",&save)) {
        line[strcspn(line,"\r")]=0;
        char *eq=strchr(line,'='); if (!eq) continue;
        *eq++=0;
#define FIELD(key,dst) if(!strcmp(line,key)){put(dst,sizeof(dst),eq);continue;}
    FIELD("IP",s->ip) FIELD("PING",s->ping) FIELD("PORT",s->port) FIELD("DISK_COUNT",s->disk_count)
        FIELD("REFRESH",s->refresh) FIELD("CMDLINE",s->cmdline)
        FIELD("MODEL",s->model) FIELD("SERIAL",s->serial) FIELD("MAC",s->mac)
        FIELD("BUILD",s->build) FIELD("UPDATE",s->update) FIELD("PLATFORM",s->platform)
        FIELD("LKM_VERSION",s->lkm_version) FIELD("MODULES_VERSION",s->modules_version)
        FIELD("MODULE_TYPE",s->module_type) FIELD("LOADER_VERSION",s->loader_version)
        FIELD("CPU",s->cpu) FIELD("THREADS",s->threads)
        FIELD("DMI",s->dmi) FIELD("BOOT",s->boot) FIELD("HBA_COUNT",s->hba_count)
        FIELD("PCI_NIC_COUNT",s->pci_nic_count) FIELD("GPU_COUNT",s->gpu_count)
        FIELD("SATA_COUNT",s->sata_count) FIELD("NVME_COUNT",s->nvme_count)
#undef FIELD
        if (!strcmp(line,"NIC") && s->nic_rows<MAX_NICS)
            put(s->nics[s->nic_rows++],sizeof(s->nics[0]),eq);
        else if (!strcmp(line,"GPU") && s->gpu_rows<MAX_GPUS)
            put(s->gpus[s->gpu_rows++],sizeof(s->gpus[0]),eq);
        else if (!strcmp(line,"DISK") && s->disk_rows<MAX_DISKS)
            put(s->disks[s->disk_rows++],sizeof(s->disks[0]),eq);
    }
    return 0;
}

static void restore_display(struct display *d)
{
    if (d->fd < 0)
        return;

    if (d->modeset_active) {
        if (d->original_crtc_valid && d->original_crtc.fb_id &&
            d->original_crtc.mode_valid) {
            struct drm_mode_crtc restore=d->original_crtc;
            restore.set_connectors_ptr=U64(&d->connector);
            restore.count_connectors=1;
            if (ioctl_ok(d->fd, DRM_IOCTL_MODE_SETCRTC, &restore) < 0)
                fprintf(stderr,"KMS original display restore failed: %s\n",strerror(errno));
        } else {
            struct drm_mode_crtc disable={.crtc_id=d->crtc};
            if (ioctl_ok(d->fd, DRM_IOCTL_MODE_SETCRTC, &disable) < 0)
                fprintf(stderr,"KMS display disable failed: %s\n",strerror(errno));
        }
    }

    if (d->fb.fb_id)
        ioctl_ok(d->fd, DRM_IOCTL_MODE_RMFB, &d->fb.fb_id);
    if (d->pixels && d->dumb.size)
        munmap(d->pixels, d->dumb.size);
    if (d->dumb.handle) {
        struct drm_mode_destroy_dumb destroy={.handle=d->dumb.handle};
        ioctl_ok(d->fd, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
    }
    ioctl_ok(d->fd, DRM_IOCTL_DROP_MASTER, NULL);
    close(d->fd);
    d->fd=-1;
}

int main(int argc, char **argv)
{
    if (argc < 2 || argc > 3) {
        fprintf(stderr,"usage: %s STATUS_FILE [DRIVER_NAME]\n",argv[0]);
        return 2;
    }
    const char *driver_filter = argc == 3 ? argv[2] : NULL;
    if (driver_filter)
        fprintf(stderr,"KMS target driver: %s\n",driver_filter);
    struct display displays[MAX_DRM_CARDS]={{0}};
    for (int card=0; card<MAX_DRM_CARDS; card++)
        displays[card].fd=-1;
    char prev[4096]="";
    time_t last_render=0;
    struct sigaction action={0};
    action.sa_handler=stop_display;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM,&action,NULL);
    sigaction(SIGINT,&action,NULL);
    while (running) {
        char status[4096];
        if (load_status(argv[1],status,sizeof(status)) == 0) {
            int changed=strcmp(status,prev)!=0;
            char copy[4096]; snprintf(copy,sizeof(copy),"%s",status);
            struct status s;
            if (parse_status(copy,&s)==0) {
                for (int card=0; card<MAX_DRM_CARDS; card++) {
                    if (displays[card].fd < 0) {
                        char path[32]; snprintf(path,sizeof(path),"/dev/dri/card%d",card);
                        char driver_name[128];
                        if (driver_filter &&
                            (card_driver_name((unsigned int)card, driver_name,
                                              sizeof(driver_name)) < 0 ||
                             strcmp(driver_name, driver_filter) != 0))
                            continue;
                        int fd=open(path,O_RDWR|O_CLOEXEC);
                        if (fd<0) continue;
                        if (ioctl_ok(fd,DRM_IOCTL_SET_MASTER,NULL)<0) { close(fd); continue; }
                        displays[card].fd=fd;
                        displays[card].card_index=(unsigned int)card;
                        if (setup_display(&displays[card])<0) {
                            int saved_errno=errno;
                            fprintf(stderr,"%s: DRM/KMS setup: %s\n",path,strerror(saved_errno));
                            restore_display(&displays[card]);
                            memset(&displays[card],0,sizeof(displays[card]));
                            displays[card].fd=-1;
                        }
                    }
                }
                time_t now=time(NULL);
                if (changed || now-last_render>=2) {
                    int rendered=0;
                    for (int card=0; card<MAX_DRM_CARDS; card++) {
                        if (displays[card].fd < 0) continue;
                        render(&displays[card],&s);
                        rendered=1;
                    }
                    if (rendered) {
                        if (!last_render)
                            fprintf(stderr,"KMS status parsed: disks=%s refresh=%s cmdline=%zu bytes\n",
                                    s.disk_count,s.refresh,strlen(s.cmdline));
                        snprintf(prev,sizeof(prev),"%s",status);
                        last_render=now;
                    }
                }
            }
        }
        struct timespec ts={.tv_sec=1,.tv_nsec=0}; nanosleep(&ts,NULL);
    }
    for (int card=0; card<MAX_DRM_CARDS; card++)
        restore_display(&displays[card]);
    return 0;
}
