# Ironbrew1 API examples

Client examples for the [Ironbrew1](https://ironbrew1.com) obfuscation API in many languages.

Every example does the same thing:

1. `POST /obfuscate?platform=...&aggressiveOptimizations=...&intenseVmScrambling=...&enableVmCompression=...`
   with the contents of `input.lua` as a `text/plain` body and your API key in the `Key` header.
   The response contains `uploadGuid` and `statusUrl`.
2. Poll `statusUrl` (waiting a little longer each time) until `status` is `completed` or `failed`.
3. Download the result from `downloadUrl` and save it as `output.lua`.

Replace `IB1-APIKEYHERE` in the example you use with your API key, put your script in `input.lua`
next to it, and run it from inside its folder.

> The queue request answers with `202 Accepted`, so treat any `2xx` status as success.
>
> Send a descriptive `User-Agent` if your HTTP library's default one is rejected (Python's `urllib` default gets a `403`).

## Examples

| Language | Folder | Run | Needs | Tested |
| --- | --- | --- | --- | --- |
| Ada | [`Examples/Ada`](Examples/Ada) | `gnatmake main.adb -largs -lcurl && ./main` | GNAT, libcurl | Yes |
| Assembly (x86-64, NASM) | [`Examples/Assembly`](Examples/Assembly) | `nasm -f elf64 main.asm -o main.o && gcc -no-pie main.o -o main -lcurl && ./main` | Linux x86-64, NASM, libcurl | Yes |
| AutoHotkey v2 | [`Examples/AutoHotkey`](Examples/AutoHotkey) | `AutoHotkey64.exe /ErrorStdOut script.ahk` | Windows | Yes |
| Ballerina | [`Examples/Ballerina`](Examples/Ballerina) | `bal run` | Ballerina 2201 (Swan Lake) | Yes |
| Batch | [`Examples/Batch`](Examples/Batch) | `script.bat` | Windows 10+ (curl.exe, PowerShell) | Yes |
| C | [`Examples/C`](Examples/C) | `gcc main.c -o main -lcurl && ./main` | libcurl | Yes |
| C# | [`Examples/CSharp`](Examples/CSharp) | `dotnet run` | .NET 8 | Yes |
| CHICKEN Scheme | [`Examples/ChickenScheme`](Examples/ChickenScheme) | `csi -s script.scm` | CHICKEN 5, eggs: http-client, medea, srfi-18, openssl | Yes |
| C++ | [`Examples/Cpp`](Examples/Cpp) | `g++ -std=c++17 main.cpp -o main -lcurl && ./main` | libcurl | Yes |
| Clojure | [`Examples/Clojure`](Examples/Clojure) | `clojure -M script.clj` | Clojure CLI | Yes |
| COBOL | [`Examples/COBOL`](Examples/COBOL) | `cobc -x -free main.cob -o main -lcurl && ./main` | GnuCOBOL 3, libcurl | Yes |
| CoffeeScript | [`Examples/CoffeeScript`](Examples/CoffeeScript) | `coffee script.coffee` | Node 18+, coffeescript | Yes |
| Common Lisp | [`Examples/CommonLisp`](Examples/CommonLisp) | `sbcl --non-interactive --load script.lisp` | SBCL, Quicklisp, OpenSSL | Yes |
| Crystal | [`Examples/Crystal`](Examples/Crystal) | `crystal run main.cr` | Crystal | Yes |
| curl (Bash) | [`Examples/Curl`](Examples/Curl) | `./curl.sh` | curl, jq | Yes |
| D | [`Examples/D`](Examples/D) | `ldc2 -run main.d` | LDC or DMD, libcurl | Yes |
| Dart | [`Examples/Dart`](Examples/Dart) | `dart main.dart` | Dart 3 | Yes |
| Elixir | [`Examples/Elixir`](Examples/Elixir) | `elixir script.exs` | Elixir 1.17+, OTP 27+ | Yes |
| Emacs Lisp | [`Examples/EmacsLisp`](Examples/EmacsLisp) | `emacs --batch -l script.el` | Emacs 27+ with GnuTLS | Yes |
| Erlang | [`Examples/Erlang`](Examples/Erlang) | `escript script.escript` | OTP 27+ | Yes |
| F# | [`Examples/FSharp`](Examples/FSharp) | `dotnet fsi script.fsx` | .NET 8 | Yes |
| Fennel | [`Examples/Fennel`](Examples/Fennel) | `fennel script.fnl` | Fennel, LuaSocket, LuaSec, dkjson | Yes |
| Fish | [`Examples/Fish`](Examples/Fish) | `fish script.fish` | fish, curl, jq | Yes |
| Forth | [`Examples/Forth`](Examples/Forth) | `gforth main.fs` | gforth, gcc, GNU libtool, libcurl dev headers | Yes |
| Fortran | [`Examples/Fortran`](Examples/Fortran) | `gfortran main.f90 -o main -lcurl && ./main` | gfortran, libcurl | Yes |
| Gauche Scheme | [`Examples/Gauche`](Examples/Gauche) | `gosh script.scm` | Gauche 0.9.15+ with TLS | Yes |
| Gleam | [`Examples/Gleam`](Examples/Gleam) | `gleam run` | Gleam, Erlang/OTP | Yes |
| Go | [`Examples/Go`](Examples/Go) | `go run .` | Go 1.21+ | Yes |
| Groovy | [`Examples/Groovy`](Examples/Groovy) | `groovy script.groovy` | Groovy, Java 11+ | Yes |
| Guile Scheme | [`Examples/Guile`](Examples/Guile) | `guile script.scm` | Guile 3, guile-gnutls | Yes |
| Haskell | [`Examples/Haskell`](Examples/Haskell) | `cabal run Main.hs` | cabal 3.8+ | Yes |
| Haxe | [`Examples/Haxe`](Examples/Haxe) | `haxe --main Main --python main.py && python3 main.py` | Haxe | Yes |
| Hy | [`Examples/Hy`](Examples/Hy) | `hy script.hy` | hy, requests | Yes |
| Java | [`Examples/Java`](Examples/Java) | `java Main.java` | Java 11+ | Yes |
| JavaScript | [`Examples/JavaScript`](Examples/JavaScript) | `node index.js` | Node 18+ (or Bun) | Yes |
| Julia | [`Examples/Julia`](Examples/Julia) | `julia script.jl` | Julia | Yes |
| Kotlin | [`Examples/Kotlin`](Examples/Kotlin) | `kotlinc Main.kt -include-runtime -d main.jar && java -jar main.jar` | Kotlin, Java 11+ | Yes |
| Lua (Roblox Studio plugin) | [`Tools/RobloxPlugin.luau`](Tools/RobloxPlugin.luau) | install as a plugin | Roblox Studio | Yes |
| Lua (standalone) | [`Examples/LuaStandalone`](Examples/LuaStandalone) | `lua script.lua` | LuaSocket, LuaSec, dkjson | Yes |
| Luau (Lune) | [`Examples/Luau`](Examples/Luau) | `lune run script.luau` | [Lune](https://lune-org.github.io/docs) | Yes |
| Modula-2 | [`Examples/Modula2`](Examples/Modula2) | `gm2 main.mod -o main -lcurl && ./main` | GNU Modula-2 (gm2), libcurl | Yes |
| MoonScript | [`Examples/MoonScript`](Examples/MoonScript) | `moon script.moon` | MoonScript, LuaSocket, LuaSec, dkjson | Yes |
| Nim | [`Examples/Nim`](Examples/Nim) | `nim c -d:ssl -r main.nim` | Nim, OpenSSL | Yes |
| Nushell | [`Examples/Nushell`](Examples/Nushell) | `nu script.nu` | Nushell 0.90+ | Yes |
| Objective-C | [`Examples/ObjectiveC`](Examples/ObjectiveC) | see the header of `main.m` | GNUstep or macOS | Yes |
| OCaml | [`Examples/OCaml`](Examples/OCaml) | `dune exec ./main.exe` | opam: dune, cohttp-lwt-unix, tls-lwt, ca-certs, mirage-crypto-rng, digestif, yojson | Yes |
| Odin | [`Examples/Odin`](Examples/Odin) | `odin run .` | Odin, libcurl | Yes |
| Pascal | [`Examples/Pascal`](Examples/Pascal) | `fpc main.pas && ./main` | Free Pascal 3.2+, OpenSSL dev libs | Yes |
| Perl | [`Examples/Perl`](Examples/Perl) | `perl script.pl` | HTTP::Tiny, JSON::PP, IO::Socket::SSL | Yes |
| PHP | [`Examples/PHP`](Examples/PHP) | `php index.php` | PHP 8.1+ with curl | Yes |
| Pike | [`Examples/Pike`](Examples/Pike) | `pike script.pike` | Pike 8 with SSL | Yes |
| PowerShell | [`Examples/PowerShell`](Examples/PowerShell) | `pwsh script.ps1` | PowerShell 5.1+ | Yes |
| Prolog | [`Examples/Prolog`](Examples/Prolog) | `swipl script.pl` | SWI-Prolog 9+ | Yes |
| Python | [`Examples/Python`](Examples/Python) | `python Python.py` | requests | Yes |
| Python (standard library only) | [`Examples/PythonStdlib`](Examples/PythonStdlib) | `python main.py` | Python 3 | Yes |
| R | [`Examples/R`](Examples/R) | `Rscript script.R` | httr, jsonlite | Yes |
| Racket | [`Examples/Racket`](Examples/Racket) | `racket script.rkt` | Racket | Yes |
| Raku | [`Examples/Raku`](Examples/Raku) | `raku script.raku` | HTTP::UserAgent, JSON::Fast, IO::Socket::SSL | Yes |
| Ruby | [`Examples/Ruby`](Examples/Ruby) | `ruby script.rb` | Ruby 3 | Yes |
| Rust | [`Examples/Rust`](Examples/Rust) | `cargo run` | Rust 2024 edition | Yes |
| Scala | [`Examples/Scala`](Examples/Scala) | `scala-cli run Main.scala` | scala-cli | Yes |
| Smalltalk (Pharo) | [`Examples/Smalltalk`](Examples/Smalltalk) | `pharo --headless Pharo.image eval "$(cat script.st)"` | Pharo 10+ | Yes |
| Teal | [`Examples/Teal`](Examples/Teal) | `tl run script.tl` | Teal, LuaSocket, LuaSec, dkjson | Yes |
| Swift | [`Examples/Swift`](Examples/Swift) | `swift main.swift` | Swift 5.9+ | Yes |
| Tcl | [`Examples/Tcl`](Examples/Tcl) | `tclsh script.tcl` | Tcl 8.6, tcllib, TclTLS | Yes |
| TypeScript (Deno) | [`Examples/TypeScript`](Examples/TypeScript) | `deno run -A main.ts` | Deno | Yes |
| V | [`Examples/V`](Examples/V) | `v run main.v` | V | Yes |
| Vala | [`Examples/Vala`](Examples/Vala) | `valac --pkg libsoup-3.0 --pkg json-glib-1.0 main.vala && ./main` | valac, libsoup 3, json-glib, glib-networking | Yes |
| VBScript | [`Examples/VBScript`](Examples/VBScript) | `cscript //nologo script.vbs` | Windows | Yes |
| Visual Basic .NET | [`Examples/VisualBasic`](Examples/VisualBasic) | `dotnet run` | .NET 8 | Yes |
| Visual Studio Code extension | [`Tools/VSCode`](Tools/VSCode) | install the `.vsix` | VS Code 1.96+ | Yes (client + activation) |
| Zig | [`Examples/Zig`](Examples/Zig) | `zig run main.zig` | Zig 0.14 | Yes |

"Tested" means the example was run against the live API and produced an obfuscated `output.lua`.
The Windows examples were tested in a Windows 10 Enterprise Evaluation VM.

The Ada, Assembly, COBOL, Forth, Fortran and Modula-2 examples call libcurl directly (the API is HTTPS-only, and a TLS
stack isn't something you write in raw assembly). They stream the request and response bodies through C
`FILE*` handles, so no callbacks are needed.

## Options

| Option | Values |
| --- | --- |
| `platform` | `roblox`, `luau`, `universal` |
| `aggressiveOptimizations` | `0`, `1`, `2` |
| `intenseVmScrambling` | `false`, `true` |
| `enableVmCompression` | `false`, `true` |
