
    ███████╗    ██╗███╗   ███╗██████╗  █████╗  ██████╗████████╗
    ╚══▓▓▓╔╝    ▓▓║▓▓▓▓╗ ▓▓▓▓║▓▓╔══▓▓╗▓▓╔══▓▓╗▓▓╔════╝╚══▓▓╔══╝
      ▒▒▒╔╝     ▒▒║▒▒╔▒▒▒▒╔▒▒║▒▒▒▒▒▒╔╝▒▒▒▒▒▒▒║▒▒║        ▒▒║   
     ░░░╔╝      ░░║░░║╚░░╔╝░░║░░╔═══╝ ░░╔══░░║░░║        ░░║   
    ░░░░░░░╗    ░░║░░║ ╚═╝ ░░║░░║     ░░║  ░░║╚░░░░░░╗   ░░║   
    ╚══════╝    ╚═╝╚═╝     ╚═╝╚═╝     ╚═╝  ╚═╝ ╚═════╝   ╚═╝   

    ░░░░▒▒▒▒▒▒▒▓▓▓▓▓▓▓▓▓██████████████▓▓▓▓▓▓▓▓▓▓▒▒▒▒▒▒▒▒▒▒░░░░╗
    ╚═════════════════════════════════════════════════════════╝
                                                           
Z impact is a ZIG game engine for creating 2d action games. It's well suited
for jump'n'runs, twin stick shooters, top-down dungeon crawlers and others with 
a focus on pixel art.

This is NOT a general purpose game engine akin to Godot, Unreal or Unity. At
this stage, it is also quite experimental and lacking documentation. Expect
problems.

Z impact is more a framework than it is a library, meaning that you have to
adhere to a structure, in code and file layout, that is prescribed by the 
engine. You do not call Z impact, Z impact _calls you_.

Games made with Z impact can be compiled for Linux, macOS, Windows (through 
the usual hoops) and for the web with WASM. There are currently only one "platform 
backend": Sokol and one renderer by OS: OpenGL (Linux), Metal (mac OS), Direct-X (Windows).

Z impact is a port of the orginal game engine [high_impact](https://github.com/phoboslab/high_impact/tree/master) made by phoboslab.

## Examples

- [Biolab Disaster](https://github.com/scemino/z_biolab): A jump'n'gun 
platformer, displaying many of Z impacts capabilities.
- [Drop](https://github.com/scemino/z_impact/tree/main/samples/zdrop): A minimal arcade game with
randomly generated levels


## Compiling

To compile and run the sample game Drop

### Linux/Windows/macOS/

```shell
zig build run
```

### Emscripten

```shell
zig build -Dtarget=wasm32-emscripten run 
```

## Documentation

There's not much at the moment. Most of Z impact's functionality is 
documented in the header files with this README giving a general overview.
It's best to read [the blog post](https://phoboslab.org/log/2024/08/high_impact)
for an overview and the source for all the details.


## Assets

At this time, Z impact can only load images in QOI format and sounds & music 
in QOA format. The tools to convert PNG to QOI and WAV to QOA are bundled in 
this repository and can be integrated in your build step.

Game levels can be loaded from .json files. A tile editor to create these levels
is part of Z impact: `weltmeister.html` which can be launched with a simple
double click from your local copy.

## Libraries used

- Sokol App, Audio and Time: https://github.com/floooh/sokol
- stb_image.h and stb_image_write.h https://github.com/nothings/stb
- QOI Image Format: https://github.com/phoboslab/qoi
- QOA Audio Format: https://github.com/phoboslab/qoa

## License

All Z impact code is MIT Licensed, though some of the libraries 
come with their own (permissive) license. Check the header files.
