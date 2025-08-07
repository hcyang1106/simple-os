# topmost CMakeLists.txt, the settings will be inherited by sub CMakeLists.txts
cmake_minimum_required(VERSION 3.10)

# show the detailed compiling process
set(CMAKE_VERBOSE_MAKEFILE on)

# prefix of gcc
if (CMAKE_HOST_WIN32 OR CMAKE_HOST_APPLE)
    set(TOOL_PREFIX  "x86_64-elf-")
elseif (CMAKE_HOST_WIN32)
    set(TOOL_PREFIX  "x86_64-linux-gnu-")
endif ()

# set(TOOL_PREFIX  "x86_64-elf-")
# set(TOOL_PREFIX  "i686-elf-")
set(CMAKE_SYSTEM_NAME "Generic")
set(CMAKE_SYSTEM_VERSION "0.0.0")

# compiler settings
set(CMAKE_C_COMPILER "${TOOL_PREFIX}gcc")
# -g => generate debug info, -c => without linking, -O0 => without optimization
# -fno-pie => without generating address independent code (out code should be fixed on certain locations)
# can add -DRELEASE when release
set(CMAKE_C_FLAGS "-g -c -O0 -m32 -fno-pie -fno-stack-protector -fno-asynchronous-unwind-tables")

# assembler settings
set(CMAKE_ASM_COMPILER "${TOOL_PREFIX}gcc")
set(CMAKE_ASM_FLAGS "-m32 -g")
set(CMAKE_ASM_SOURCE_FILE_EXTENSIONS "asm")

# linker
set(LINKER_TOOL "${TOOL_PREFIX}ld")

# other tools
set(OBJCOPY_TOOL "${TOOL_PREFIX}objcopy")
set(OBJDUMP_TOOL "${TOOL_PREFIX}objdump")
set(READELF_TOOL "${TOOL_PREFIX}readelf")

# project name is "os"
project(os LANGUAGES C)  
enable_language(ASM)

# search directory for header files
include_directories(
    ${PROJECT_SOURCE_DIR}/source
    ${PROJECT_SOURCE_DIR}/source/kernel/include
    ${PROJECT_SOURCE_DIR}/../newlib/i686-elf/include
)

# include kernel and applications
add_subdirectory(./source/boot)
add_subdirectory(./source/loader)
add_subdirectory(./source/kernel)
add_subdirectory(./source/applib)
add_subdirectory(./source/shell)
add_subdirectory(./source/init)
add_subdirectory(./source/loop)

# libapp has to be created before these specific modules
# add_dependencies(init app)
add_dependencies(shell app)
add_dependencies(kernel app)
add_dependencies(loop app)
add_dependencies(kernel init)



# when we include header files as <>, the default search directory is usually /usr/include
# when we include header files as "", the order of directory search is
# 1. current directory of the file that contains ""
# 2. -I option's included directories
# 3. default header search directory (usr/include)

# example: gcc -I/project/includes -I/project/src main.c
# 1. directory of main
# 2. -I directories
# 3. usr/include

# Q: Why do we separate different .c files rather than writing all codes in a .c file?
# A: Because when we fix something and recompile, we do not need to compile the whole code base.
# Since source files are compiled separately, we need some way to know what is exported by other files,
# this is why "header files are needed".
# A: There are also other benefits, such as 1. easier to do unit testing 2. easier to work together (avoid conflicts)
# 3. modules depend on one another using "interfaces" instead of "knowing all the details"

# Usually, static functions are not declared in the header files
# because other source files aren't using it

# Functions or variables without "static" keyword has external linkage by default,
# which means everyone could use them

# However, before using them compiler needs to see the declaration first,
# that's why we need header files or declare it at the beginning a file.
# And for variables we use the "extern" keyword to declare them.

# Why do we need a top layer CMakeLists.txt?
# A: I think the reason is we can do some overall settings for the whole project,
# otherwise some common settings need to appear in every CMakeLists.txt.