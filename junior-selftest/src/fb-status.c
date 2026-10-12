/* Minimal Linux framebuffer status renderer for the junior self-test.
 * Copyright (C) 2026 PeterSuh-Q3. See repository LICENSE.
 * Usage: fb-status LINE [LINE ...]. ASCII is rendered in uppercase.
 */
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

/* Each character is five rows of three pixels. */
static const char *glyph(char c) {
    switch (c) {
    case 'A': return "010101111101101"; case 'B': return "110101110101110";
    case 'C': return "011100100100011"; case 'D': return "110101101101110";
    case 'E': return "111100110100111"; case 'F': return "111100110100100";
    case 'G': return "011100101101011"; case 'H': return "101101111101101";
    case 'I': return "111010010010111"; case 'J': return "001001001101010";
    case 'K': return "101101110101101"; case 'L': return "100100100100111";
    case 'M': return "101111111101101"; case 'N': return "101111111111101";
    case 'O': return "010101101101010"; case 'P': return "110101110100100";
    case 'Q': return "010101101111011"; case 'R': return "110101110101101";
    case 'S': return "011100010001110"; case 'T': return "111010010010010";
    case 'U': return "101101101101111"; case 'V': return "101101101101010";
    case 'W': return "101101111111101"; case 'X': return "101101010101101";
    case 'Y': return "101101010010010"; case 'Z': return "111001010100111";
    case '0': return "111101101101111"; case '1': return "010110010010111";
    case '2': return "110001111100111"; case '3': return "110001110001110";
    case '4': return "101101111001001"; case '5': return "111100110001110";
    case '6': return "011100110101010"; case '7': return "111001010010010";
    case '8': return "010101010101010"; case '9': return "010101011001110";
    case ':': return "000010000010000"; case '.': return "000000000000010";
    case '-': return "000000111000000"; case '/': return "001001010100100";
    case '+': return "000010111010000"; case '_': return "000000000000111";
    case '?': return "110001010000010"; case '=': return "000111000111000";
    default: return "000000000000000";
    }
}

static uint32_t color(const struct fb_var_screeninfo *v, unsigned r,
                      unsigned g, unsigned b) {
    return ((r >> (8 - v->red.length)) << v->red.offset) |
           ((g >> (8 - v->green.length)) << v->green.offset) |
           ((b >> (8 - v->blue.length)) << v->blue.offset);
}

static void pixel(unsigned char *fb, const struct fb_fix_screeninfo *f,
                  const struct fb_var_screeninfo *v, unsigned x, unsigned y,
                  uint32_t value) {
    size_t at = (size_t)(y + v->yoffset) * f->line_length +
                (size_t)(x + v->xoffset) * (v->bits_per_pixel / 8);
    if (at + v->bits_per_pixel / 8 > f->smem_len) return;
    if (v->bits_per_pixel == 16) {
        uint16_t c = (uint16_t)value;
        memcpy(fb + at, &c, 2);
    } else memcpy(fb + at, &value, 4);
}

int main(int argc, char **argv) {
    struct fb_fix_screeninfo f;
    struct fb_var_screeninfo v;
    unsigned char *fb;
    int fd = open("/dev/fb0", O_RDWR);
    if (fd < 0) { perror("/dev/fb0"); return 2; }
    if (ioctl(fd, FBIOGET_FSCREENINFO, &f) ||
        ioctl(fd, FBIOGET_VSCREENINFO, &v)) { perror("fb ioctl"); close(fd); return 2; }
    if (f.type != FB_TYPE_PACKED_PIXELS || v.grayscale ||
        (v.bits_per_pixel != 16 && v.bits_per_pixel != 32) ||
        !v.red.length || !v.green.length || !v.blue.length ||
        v.red.length > 8 || v.green.length > 8 || v.blue.length > 8 ||
        v.xres < 320 || v.yres < 160 || !f.smem_len) {
        fprintf(stderr, "unsupported framebuffer: %ux%u %u bpp type %u\n",
                v.xres, v.yres, v.bits_per_pixel, f.type);
        close(fd); return 2;
    }
    fb = mmap(NULL, f.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (fb == MAP_FAILED) { perror("fb mmap"); close(fd); return 2; }
    unsigned scale = v.xres >= 800 ? 3 : 2;
    unsigned width = v.xres < 800 ? v.xres : 800;
    unsigned height = 28 + (argc > 1 ? (unsigned)(argc - 1) : 1) * 8 * scale;
    if (height > v.yres) height = v.yres;
    uint32_t bg = color(&v, 8, 18, 34), fg = color(&v, 230, 245, 255);
    for (unsigned y = 0; y < height; ++y)
        for (unsigned x = 0; x < width; ++x) pixel(fb, &f, &v, x, y, bg);
    for (int line = 1; line < argc; ++line) {
        unsigned y0 = 12 + (unsigned)(line - 1) * 8 * scale;
        if (y0 + 5 * scale > height) break;
        for (unsigned col = 0; argv[line][col]; ++col) {
            unsigned x0 = 12 + col * 4 * scale;
            if (x0 + 3 * scale > width) break;
            char c = argv[line][col];
            if (c >= 'a' && c <= 'z') c -= 32;
            const char *bits = glyph(c);
            for (unsigned row = 0; row < 5; ++row)
                for (unsigned bit = 0; bit < 3; ++bit)
                    if (bits[row * 3 + bit] == '1')
                        for (unsigned dy = 0; dy < scale; ++dy)
                            for (unsigned dx = 0; dx < scale; ++dx)
                                pixel(fb, &f, &v, x0 + bit * scale + dx,
                                      y0 + row * scale + dy, fg);
        }
    }
    munmap(fb, f.smem_len);
    close(fd);
    return 0;
}
