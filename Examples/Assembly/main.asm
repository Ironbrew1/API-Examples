; x86-64 Linux, NASM syntax. Build and run:
;   nasm -f elf64 main.asm -o main.o && gcc -no-pie main.o -o main -lcurl && ./main
;
; NOTE: the API is HTTPS-only, so a TLS stack is needed. Writing one in raw assembly
; isn't realistic, so this program is real assembly that calls libcurl (and a few libc
; functions) through the System V C ABI. The request/response bodies are streamed through
; C FILE* handles, so no callbacks are needed.

default rel

global main

extern curl_easy_init, curl_easy_setopt, curl_easy_perform, curl_easy_getinfo, curl_easy_cleanup
extern curl_slist_append, curl_slist_free_all
extern fopen, fclose, fseek, ftell, rewind, fmemopen
extern snprintf, strstr, strchr, strlen, strcmp, memcpy
extern sleep, printf, puts, fprintf, exit, stderr

CURLOPT_WRITEDATA    equ 10001
CURLOPT_URL          equ 10002
CURLOPT_READDATA     equ 10009
CURLOPT_HTTPHEADER   equ 10023
CURLOPT_TIMEOUT      equ 13
CURLOPT_POST         equ 47
CURLOPT_POSTFIELDSIZE equ 60
CURLINFO_RESPONSE_CODE equ 0x200002

RETRY_DELAY          equ 5
MAX_WAIT             equ 240
MAX_FAILS            equ 3

section .rodata
s_base:         db "https://ironbrew1.com", 0
s_query:        db "/obfuscate?platform=roblox&aggressiveOptimizations=0&intenseVmScrambling=false&enableVmCompression=false", 0
s_key_header:   db "Key: IB1-APIKEYHERE", 0
s_content_type: db "Content-Type: text/plain", 0
s_input:        db "input.lua", 0
s_output:       db "output.lua", 0
s_rb:           db "rb", 0
s_wb:           db "wb", 0
s_w:            db "w", 0
s_fmt_url:      db "%s%s", 0
s_fmt_key:      db '"%s"', 0
s_completed:    db "completed", 0
s_failed:       db "failed", 0
f_guid:         db "uploadGuid", 0
f_status_url:   db "statusUrl", 0
f_status:       db "status", 0
f_download:     db "downloadUrl", 0

m_started:      db "Obfuscation started with GUID: %s", 10, 0
m_progress:     db "Obfuscation is still in progress. Elapsed time: %d seconds. Checking again in %d seconds.", 10, 0
m_status_fail:  db "Status check failed with status: %d (%d/%d)", 10, 0
m_completed:    db "Obfuscation completed in %d seconds", 10, 0
m_saved:        db "Saved obfuscated script to output.lua", 0
e_queue:        db "Unable to queue obfuscation: %d", 10, 0
e_checks:       db "Obfuscation failed (fails: %d | elapsed time: %d)", 10, 0
e_job:          db "Obfuscation failed (status: %s | elapsed time: %d)", 10, 0
e_download:     db "Download failed with status: %d", 10, 0

section .bss
json_buf:       resb 65536
url_buf:        resb 512
status_url:     resb 256
download_url:   resb 256
guid:           resb 64
state:          resb 32
code:           resd 1
elapsed:        resd 1
fails:          resd 1
wait_time:      resd 1

section .text

; int request(const char *url /*rdi*/, const char *input_path /*rsi, may be 0*/, FILE *out /*rdx*/)
; One libcurl request. POSTs the contents of input_path when it is not NULL and streams the
; response body into `out`. Returns the HTTP status code (0 on transport errors).
request:
    push rbp
    mov rbp, rsp
    push rbx                    ; rbx = CURL*
    push r12                    ; r12 = struct curl_slist*
    push r13                    ; r13 = input FILE* (or 0)
    push r14                    ; r14 = url
    push r15                    ; r15 = output FILE*
    sub rsp, 24                 ; [rsp] = input path, [rsp+8] = http status (long), [rsp+16] = input size
    mov r14, rdi
    mov [rsp], rsi
    mov r15, rdx
    xor r13d, r13d
    mov qword [rsp + 8], 0

    call curl_easy_init
    mov rbx, rax

    xor edi, edi
    lea rsi, [s_key_header]
    call curl_slist_append
    mov rdi, rax
    lea rsi, [s_content_type]
    call curl_slist_append
    mov r12, rax

    mov rdi, rbx
    mov esi, CURLOPT_URL
    mov rdx, r14
    xor eax, eax
    call curl_easy_setopt
    mov rdi, rbx
    mov esi, CURLOPT_HTTPHEADER
    mov rdx, r12
    xor eax, eax
    call curl_easy_setopt
    mov rdi, rbx
    mov esi, CURLOPT_TIMEOUT
    mov edx, 120
    xor eax, eax
    call curl_easy_setopt
    mov rdi, rbx
    mov esi, CURLOPT_WRITEDATA
    mov rdx, r15
    xor eax, eax
    call curl_easy_setopt

    cmp qword [rsp], 0
    je .perform
    mov rdi, [rsp]
    lea rsi, [s_rb]
    call fopen
    mov r13, rax
    mov rdi, r13                ; fseek(f, 0, SEEK_END)
    xor esi, esi
    mov edx, 2
    call fseek
    mov rdi, r13
    call ftell
    mov [rsp + 16], rax
    mov rdi, r13
    call rewind
    mov rdi, rbx
    mov esi, CURLOPT_POST
    mov edx, 1
    xor eax, eax
    call curl_easy_setopt
    mov rdi, rbx
    mov esi, CURLOPT_POSTFIELDSIZE
    mov rdx, [rsp + 16]
    xor eax, eax
    call curl_easy_setopt
    mov rdi, rbx
    mov esi, CURLOPT_READDATA
    mov rdx, r13
    xor eax, eax
    call curl_easy_setopt

.perform:
    mov rdi, rbx
    call curl_easy_perform
    test eax, eax
    jnz .cleanup
    mov rdi, rbx
    mov esi, CURLINFO_RESPONSE_CODE
    lea rdx, [rsp + 8]
    xor eax, eax
    call curl_easy_getinfo

.cleanup:
    mov rdi, rbx
    call curl_easy_cleanup
    mov rdi, r12
    call curl_slist_free_all
    test r13, r13
    jz .done
    mov rdi, r13
    call fclose
.done:
    mov rax, [rsp + 8]
    add rsp, 24
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; int api(const char *url /*rdi*/, const char *input_path /*rsi*/)
; Like request, but the (small, JSON) response body is collected in json_buf.
api:
    push rbx
    push r12
    sub rsp, 8                  ; [rsp] = FILE* for json_buf
    mov rbx, rdi
    mov r12, rsi
    lea rdi, [json_buf]
    mov esi, 65536
    lea rdx, [s_w]
    call fmemopen
    mov [rsp], rax
    mov rdi, rbx
    mov rsi, r12
    mov rdx, rax
    call request
    mov ebx, eax
    mov rdi, [rsp]
    call fclose
    mov eax, ebx
    add rsp, 8
    pop r12
    pop rbx
    ret

; int download(const char *url /*rdi*/): streams the response straight into output.lua
download:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    lea rdi, [s_output]
    lea rsi, [s_wb]
    call fopen
    mov r12, rax
    mov rdi, rbx
    xor esi, esi
    mov rdx, r12
    call request
    mov ebx, eax
    mov rdi, r12
    call fclose
    mov eax, ebx
    add rsp, 8
    pop r12
    pop rbx
    ret

; void field(const char *json /*rdi*/, const char *name /*rsi*/, char *out /*rdx*/, size_t outsize /*rcx*/)
; Pulls a string value out of a flat JSON object into `out` ("" if missing or not a string).
field:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 80                 ; [rsp] = "\"name\"" buffer
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov r14, rsi
    mov byte [r12], 0

    mov rdi, rsp                ; snprintf(key, 80, "\"%s\"", name)
    mov esi, 80
    lea rdx, [s_fmt_key]
    mov rcx, r14
    xor eax, eax
    call snprintf

    mov rdi, rbx                ; p = strstr(json, key)
    mov rsi, rsp
    call strstr
    test rax, rax
    jz .out
    mov r14, rax

    mov rdi, rsp
    call strlen
    add r14, rax                ; skip the key itself

    mov rdi, r14                ; p = strchr(p, ':')
    mov esi, ':'
    call strchr
    test rax, rax
    jz .out
    cmp byte [rax + 1], '"'     ; only string values
    jne .out
    lea r14, [rax + 2]          ; start of the value

    mov rdi, r14                ; end = strchr(start, '"')
    mov esi, '"'
    call strchr
    test rax, rax
    jz .out
    sub rax, r14                ; length of the value
    lea rcx, [r13 - 1]
    cmp rax, rcx
    cmova rax, rcx              ; clamp to outsize - 1
    mov rbx, rax
    mov rdi, r12
    mov rsi, r14
    mov rdx, rax
    call memcpy
    mov byte [r12 + rbx], 0
.out:
    add rsp, 80
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; int main(void)
main:
    push rbp
    mov rbp, rsp

    ; queue the job: POST <base>/obfuscate?... with input.lua as the body
    lea rdi, [url_buf]
    mov esi, 512
    lea rdx, [s_fmt_url]
    lea rcx, [s_base]
    lea r8, [s_query]
    xor eax, eax
    call snprintf
    lea rdi, [url_buf]
    lea rsi, [s_input]
    call api
    mov [code], eax
    cmp eax, 200
    jl .queue_failed
    cmp eax, 299
    jg .queue_failed

    lea rdi, [json_buf]
    lea rsi, [f_status_url]
    lea rdx, [status_url]
    mov ecx, 256
    call field
    lea rdi, [json_buf]
    lea rsi, [f_guid]
    lea rdx, [guid]
    mov ecx, 64
    call field
    lea rdi, [m_started]
    lea rsi, [guid]
    xor eax, eax
    call printf

.poll:
    add dword [wait_time], RETRY_DELAY
    mov edi, [wait_time]
    call sleep
    mov eax, [wait_time]
    add [elapsed], eax

    lea rdi, [url_buf]
    mov esi, 512
    lea rdx, [s_fmt_url]
    lea rcx, [s_base]
    lea r8, [status_url]
    xor eax, eax
    call snprintf
    lea rdi, [url_buf]
    xor esi, esi
    call api
    mov [code], eax
    cmp eax, 200
    jl .status_bad
    cmp eax, 299
    jg .status_bad

    lea rdi, [json_buf]
    lea rsi, [f_status]
    lea rdx, [state]
    mov ecx, 32
    call field

    lea rdi, [state]
    lea rsi, [s_completed]
    call strcmp
    test eax, eax
    jz .completed
    lea rdi, [state]
    lea rsi, [s_failed]
    call strcmp
    test eax, eax
    jz .job_failed
    cmp dword [elapsed], MAX_WAIT
    jge .job_failed

    lea rdi, [m_progress]
    mov esi, [elapsed]
    mov edx, [wait_time]
    add edx, RETRY_DELAY
    xor eax, eax
    call printf
    jmp .poll

.status_bad:
    inc dword [fails]
    lea rdi, [m_status_fail]
    mov esi, [code]
    mov edx, [fails]
    mov ecx, MAX_FAILS
    xor eax, eax
    call printf
    cmp dword [fails], MAX_FAILS
    jge .checks_failed
    cmp dword [elapsed], MAX_WAIT
    jge .checks_failed
    jmp .poll

.completed:
    lea rdi, [m_completed]
    mov esi, [elapsed]
    xor eax, eax
    call printf
    lea rdi, [json_buf]
    lea rsi, [f_download]
    lea rdx, [download_url]
    mov ecx, 256
    call field
    lea rdi, [url_buf]
    mov esi, 512
    lea rdx, [s_fmt_url]
    lea rcx, [s_base]
    lea r8, [download_url]
    xor eax, eax
    call snprintf
    lea rdi, [url_buf]
    call download
    mov [code], eax
    cmp eax, 200
    jl .download_failed
    cmp eax, 299
    jg .download_failed
    lea rdi, [m_saved]
    call puts
    xor eax, eax
    pop rbp
    ret

.queue_failed:
    mov rdi, [stderr]
    lea rsi, [e_queue]
    mov edx, [code]
    xor eax, eax
    call fprintf
    jmp .die
.download_failed:
    mov rdi, [stderr]
    lea rsi, [e_download]
    mov edx, [code]
    xor eax, eax
    call fprintf
    jmp .die
.checks_failed:
    mov rdi, [stderr]
    lea rsi, [e_checks]
    mov edx, [fails]
    mov ecx, [elapsed]
    xor eax, eax
    call fprintf
    jmp .die
.job_failed:
    mov rdi, [stderr]
    lea rsi, [e_job]
    lea rdx, [state]
    mov ecx, [elapsed]
    xor eax, eax
    call fprintf
.die:
    mov edi, 1
    call exit
