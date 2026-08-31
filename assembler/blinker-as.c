/* Reconstructed portfolio assembler. Encoding is derived from instruction_decoder.sv. */
#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LINE_SIZE 2048
#define MAX_LINES 65536
#define MAX_SYMBOLS 8192
#define MAX_MACROS 128
#define MAX_PARAMS 16
#define MAX_BODY 256
#define MEMORY_SIZE 524288

typedef struct { char *text; unsigned source; uint32_t address; } Line;
typedef struct { char name[128]; uint32_t address; } Symbol;
typedef struct {
    char name[128], params[MAX_PARAMS][128];
    unsigned nparams, count;
    char *body[MAX_BODY];
} Macro;
static Line lines[MAX_LINES];
static Symbol symbols[MAX_SYMBOLS];
static Macro macros[MAX_MACROS];
static unsigned nlines, nsymbols, nmacros, source_line;
static const char *source_path;

static void fail(const char *category, const char *format, ...) {
    fprintf(stderr, "%s:%u: %s: ", source_path, source_line, category);
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
    fputc('\n', stderr);
    exit(EXIT_FAILURE);
}
static char *copy(const char *s) {
    char *p = malloc(strlen(s) + 1);
    if (!p) fail("resource", "out of memory");
    return strcpy(p, s);
}
static void name_copy(char *dst, const char *src) {
    if (strlen(src) >= 128) fail("syntax", "identifier too long");
    strcpy(dst, src);
}
static int identifier(const char *s) {
    if (!isalpha((unsigned char)*s) && *s != '_') return 0;
    for (++s; *s; ++s)
        if (!isalnum((unsigned char)*s) && *s != '_') return 0;
    return 1;
}
static char *trim(char *s) {
    while (isspace((unsigned char)*s)) ++s;
    size_t n = strlen(s);
    while (n && isspace((unsigned char)s[n-1])) s[--n] = '\0';
    return s;
}
static unsigned tokenize(char *s, char **tokens) {
    unsigned n = 0;
    for (char *p = strtok(s, " \t,\r\n"); p; p = strtok(NULL, " \t,\r\n")) {
        if (n == MAX_PARAMS + 1) fail("syntax", "too many operands");
        tokens[n++] = p;
    }
    return n;
}
static void append(const char *s) {
    if (nlines == MAX_LINES) fail("resource", "expanded program too large");
    lines[nlines++] = (Line){copy(s), source_line, 0};
}
/* Macro calls are expanded before labels are assigned addresses. */
static void expand(const char *input, unsigned depth) {
    if (depth > 16) fail("macro", "expansion nesting exceeds 16 levels");
    char buffer[LINE_SIZE], raw[LINE_SIZE];
    strcpy(buffer, input);
    char *s = trim(buffer);
    char *colon = strchr(s, ':');
    if (colon) {
        *colon = '\0';
        if (!identifier(trim(s))) fail("syntax", "invalid label");
        snprintf(raw, sizeof raw, "%s:", trim(s));
        append(raw);
        s = trim(colon + 1);
    }
    if (!*s) return;
    strcpy(raw, s);
    char *tokens[MAX_PARAMS + 1];
    unsigned count = tokenize(s, tokens);
    for (unsigned m = 0; m < nmacros; ++m) {
        Macro *macro = &macros[m];
        if (strcmp(tokens[0], macro->name)) continue;
        if (count != macro->nparams + 1) fail("macro", "wrong argument count for %s", macro->name);
        for (unsigned l = 0; l < macro->count; ++l) {
            char expanded[LINE_SIZE];
            size_t used = 0;
            const char *p = macro->body[l];
            while (*p) {
                if (*p != '\\') {
                    if (used + 1 >= sizeof expanded) fail("macro", "expanded line too long");
                    expanded[used++] = *p++;
                    continue;
                }
                char param[128];
                unsigned len = 0;
                ++p;
                while (isalnum((unsigned char)*p) || *p == '_') {
                    if (len == sizeof param - 1) fail("macro", "parameter too long");
                    param[len++] = *p++;
                }
                param[len] = '\0';
                unsigned j;
                for (j = 0; j < macro->nparams; ++j)
                    if (!strcmp(param, macro->params[j])) break;
                if (j == macro->nparams) fail("macro", "unknown parameter %s", param);
                size_t len_arg = strlen(tokens[j+1]);
                if (used + len_arg >= sizeof expanded) fail("macro", "expanded line too long");
                memcpy(expanded + used, tokens[j+1], len_arg);
                used += len_arg;
            }
            expanded[used] = '\0';
            expand(expanded, depth + 1);
        }
        return;
    }
    append(raw);
}
static void read_source(FILE *in) {
    char buffer[LINE_SIZE];
    Macro *active = NULL;
    while (fgets(buffer, sizeof buffer, in)) {
        ++source_line;
        if (!strchr(buffer, '\n') && !feof(in)) fail("syntax", "source line too long");
        char *comment = strpbrk(buffer, ";#");
        if (comment) *comment = '\0';
        char *s = trim(buffer);
        if (!*s) continue;
        if (!strcmp(s, ".endm")) {
            if (!active) fail("macro", "unexpected .endm");
            active = NULL;
            continue;
        }
        if (!strncmp(s, ".macro", 6) && (s[6] == '\0' || isspace((unsigned char)s[6]))) {
            if (active) fail("macro", "nested definitions are unsupported");
            if (nmacros == MAX_MACROS) fail("resource", "too many macros");
            char *tokens[MAX_PARAMS + 1];
            unsigned n = tokenize(s + 6, tokens);
            if (!n || !identifier(tokens[0])) fail("macro", "expected macro name");
            for (unsigned i = 0; i < nmacros; ++i)
                if (!strcmp(macros[i].name, tokens[0])) fail("macro", "duplicate macro");
            active = &macros[nmacros++];
            name_copy(active->name, tokens[0]);
            active->nparams = n - 1;
            for (unsigned i = 1; i < n; ++i) {
                if (!identifier(tokens[i])) fail("macro", "invalid parameter");
                for (unsigned j = 1; j < i; ++j)
                    if (!strcmp(tokens[i], tokens[j])) fail("macro", "duplicate parameter");
                name_copy(active->params[i-1], tokens[i]);
            }
        } else if (active) {
            if (active->count == MAX_BODY) fail("resource", "macro body too large");
            active->body[active->count++] = copy(s);
        } else expand(s, 0);
    }
    if (ferror(in)) fail("io", "could not read input");
    if (active) fail("macro", "missing .endm");
}
static uint64_t value(const char *s) {
    if (identifier(s)) {
        for (unsigned i = 0; i < nsymbols; ++i)
            if (!strcmp(s, symbols[i].name)) return symbols[i].address;
        fail("symbol", "undefined label %s", s);
    }
    char *end;
    errno = 0;
    /* Base 0 accepts decimal, 0x hex, and C-style octal; negative values use two's complement. */
    uint64_t v = strtoull(s, &end, 0);
    if (errno || !*s || *end) fail("literal", "invalid 64-bit integer %s", s);
    if (*s == '-') {
        errno = 0;
        (void)strtoll(s, &end, 0);
        if (errno) fail("literal", "negative integer below signed 64-bit range");
    }
    return v;
}
static unsigned reg(const char *s) {
    if (s[0] != 'r' || !isdigit((unsigned char)s[1])) fail("register", "expected r0..r31, got %s", s);
    char *end;
    errno = 0;
    unsigned long r = strtoul(s+1, &end, 10);
    if (errno || *end || r > 31) fail("register", "expected r0..r31, got %s", s);
    return (unsigned)r;
}
static uint32_t encode(unsigned op, unsigned rd, unsigned rs, unsigned rt, unsigned imm) {
    return (op << 27) | (rd << 22) | (rs << 17) | (rt << 12) | (imm & 0xfff);
}
static unsigned imm12(const char *s, int low_bits, uint32_t pc, int relative) {
    uint64_t v = value(s);
    if (relative && identifier(s)) v -= pc;
    if (low_bits) {
        if (v > 4095) fail("range", "movi literal must be 0..4095");
    } else if (v > 2047 && v < UINT64_MAX - 2047) {
        fail("range", "immediate must fit signed 12 bits (-2048..2047)");
    }
    return (unsigned)(v & 0xfff);
}
typedef struct { const char *name; unsigned op; char format; } Instruction;
static const Instruction isa[] = {
    {"and",0x00,'3'}, {"or",0x01,'3'}, {"xor",0x02,'3'}, {"not",0x03,'2'},
    {"shftr",0x04,'3'}, {"shftri",0x05,'i'}, {"shftl",0x06,'3'}, {"shftli",0x07,'i'},
    {"br",0x08,'r'}, {"brr",0x09,'r'}, {"brrl",0x0a,'b'}, {"brnz",0x0b,'2'},
    {"call",0x0c,'r'}, {"return",0x0d,'0'}, {"ret",0x0d,'0'}, {"brgt",0x0e,'3'},
    {"halt",0x0f,'0'}, {"load",0x10,'m'}, {"mov",0x11,'2'}, {"movi",0x12,'u'},
    {"store",0x13,'m'}, {"addf",0x14,'3'}, {"subf",0x15,'3'},
    {"mulf",0x16,'3'}, {"divf",0x17,'3'}, {"add",0x18,'3'}, {"addi",0x19,'i'},
    {"sub",0x1a,'3'}, {"subi",0x1b,'i'}, {"mul",0x1c,'3'}, {"div",0x1d,'3'}
};
static void layout(uint32_t base) {
    uint32_t pc = base;
    for (unsigned i = 0; i < nlines; ++i) {
        Line *l = &lines[i];
        source_line = l->source;
        l->address = pc;
        size_t len = strlen(l->text);
        if (len && l->text[len-1] == ':') {
            l->text[len-1] = '\0';
            if (nsymbols == MAX_SYMBOLS) fail("resource", "too many labels");
            for (unsigned j = 0; j < nsymbols; ++j)
                if (!strcmp(symbols[j].name, l->text)) fail("symbol", "duplicate label %s", l->text);
            name_copy(symbols[nsymbols].name, l->text);
            symbols[nsymbols++].address = pc;
            l->text[0] = '\0';
            continue;
        }
        char buffer[LINE_SIZE], *tokens[MAX_PARAMS+1];
        strcpy(buffer, l->text);
        tokenize(buffer, tokens);
        unsigned bytes = !strcmp(tokens[0], "li") ? 48 : !strcmp(tokens[0], ".quad") ? 8 : 4;
        if (pc > MEMORY_SIZE - bytes) fail("range", "program exceeds processor memory");
        pc += bytes;
    }
}
static uint32_t assemble(Line *l, uint8_t *output) {
    char buffer[LINE_SIZE], *t[MAX_PARAMS+1];
    strcpy(buffer, l->text);
    unsigned n = tokenize(buffer, t);
    uint32_t words[12];
    unsigned count = 1;
    if (!strcmp(t[0], "li")) {
        if (n != 3) fail("syntax", "li expects register, value");
        unsigned rd = reg(t[1]);
        uint64_t v = value(t[2]);
        words[0] = encode(2, rd, rd, rd, 0); /* xor clears all 64 bits */
        words[1] = encode(0x12, rd, 0, 0, (unsigned)(v >> 60));
        count = 2;
        for (int shift = 48; shift >= 0; shift -= 12) {
            words[count++] = encode(7, rd, 0, 0, 12);
            words[count++] = encode(0x12, rd, 0, 0, (unsigned)(v >> shift));
        }
    } else if (!strcmp(t[0], "nop")) {
        if (n != 1) fail("syntax", "nop takes no operands");
        words[0] = encode(0x11, 0, 0, 0, 0); /* mov r0,r0: r0 is writable */
    } else if (!strcmp(t[0], ".word") || !strcmp(t[0], ".quad")) {
        if (n != 2) fail("syntax", "data directive expects one value");
        uint64_t v = value(t[1]);
        unsigned bytes = !strcmp(t[0], ".quad") ? 8 : 4;
        if (bytes == 4 && v > UINT32_MAX) fail("range", ".word expects unsigned 32-bit value");
        for (unsigned b = 0; b < bytes; ++b) output[b] = (uint8_t)(v >> (8*b));
        return bytes;
    } else {
        const Instruction *ins = NULL;
        for (size_t i = 0; i < sizeof isa / sizeof isa[0]; ++i)
            if (!strcmp(t[0], isa[i].name)) { ins = &isa[i]; break; }
        if (!ins) fail("opcode", "unknown instruction %s", t[0]);
        char f = ins->format;
        unsigned expected = (f == '0') ? 1 : (f == 'r' || f == 'b') ? 2 : (f == '3' || f == 'm') ? 4 : 3;
        if (n != expected) fail("syntax", "wrong operand count for %s", ins->name);
        unsigned rd = 0, rs = 0, rt = 0, imm = 0;
        if (f != '0' && f != 'b') rd = reg(t[1]);
        if (f == '3' || f == '2' || f == 'm') rs = reg(t[2]);
        if (f == '3') rt = reg(t[3]);
        if (f == 'i' || f == 'u') imm = imm12(t[2], f == 'u', l->address, 0);
        if (f == 'b') imm = imm12(t[1], 0, l->address, 1);
        if (f == 'm') imm = imm12(t[3], 0, l->address, 0);
        words[0] = encode(ins->op, rd, rs, rt, imm);
    }
    for (unsigned w = 0; w < count; ++w)
        for (unsigned b = 0; b < 4; ++b) output[w*4+b] = (uint8_t)(words[w] >> (8*b));
    return count * 4;
}
static void usage(void) {
    puts("Usage: blinker-as input.asm -o output [--format hex|bin] [--base address]\n"
         "Default: byte-oriented $readmemh image at 0x2000; binary omits address padding.");
}
int main(int argc, char **argv) {
    source_path = "blinker-as";
    const char *input = NULL, *output = NULL, *format = "hex";
    uint64_t base = 0x2000;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--help") || !strcmp(argv[i], "-h")) { usage(); return 0; }
        if (!strcmp(argv[i], "-o") || !strcmp(argv[i], "--format") || !strcmp(argv[i], "--base")) {
            const char *option = argv[i];
            if (++i == argc) fail("cli", "missing option value");
            if (!strcmp(option, "-o")) output = argv[i];
            else if (!strcmp(option, "--format")) format = argv[i];
            else base = value(argv[i]);
        } else if (argv[i][0] == '-' || input) fail("cli", "unexpected argument %s", argv[i]);
        else input = argv[i];
    }
    if (!input || !output) { usage(); return EXIT_FAILURE; }
    if (strcmp(format, "hex") && strcmp(format, "bin")) fail("cli", "format must be hex or bin");
    if (base >= MEMORY_SIZE || base % 4) fail("range", "base must be aligned and inside memory");
    if (!strcmp(input, output)) fail("io", "input and output paths must differ");
    source_path = input;
    FILE *in = fopen(input, "r");
    if (!in) fail("io", "cannot open input: %s", strerror(errno));
    read_source(in);
    fclose(in);
    layout((uint32_t)base);
    static uint8_t image[MEMORY_SIZE];
    uint32_t size = 0;
    for (unsigned i = 0; i < nlines; ++i) {
        if (!*lines[i].text) continue;
        source_line = lines[i].source;
        size += assemble(&lines[i], image + size);
    }
    /* Do not create an output file until parsing and encoding have succeeded. */
    FILE *out = fopen(output, "wb");
    if (!out) fail("io", "cannot open output: %s", strerror(errno));
    if (!strcmp(format, "hex")) {
        fprintf(out, "@%08" PRIx64 "\n", base);
        for (uint32_t i = 0; i < size; ++i) fprintf(out, "%02x\n", image[i]);
    } else if (fwrite(image, 1, size, out) != size) fail("io", "short write");
    int bad = ferror(out);
    if (fclose(out)) bad = 1;
    if (bad) fail("io", "could not write output");
    for (unsigned i = 0; i < nlines; ++i) free(lines[i].text);
    for (unsigned i = 0; i < nmacros; ++i)
        for (unsigned j = 0; j < macros[i].count; ++j) free(macros[i].body[j]);
    return EXIT_SUCCESS;
}
