
project(shell LANGUAGES C)  

# customized linker
# libapp and newlib should be linked to shell
# -lm -lc represents math library and c library
set(LIBS_FLAGS "-L ${CMAKE_BINARY_DIR}/source/applib/ -lapp -L ${CMAKE_BINARY_DIR}/../../newlib/i686-elf/lib -lm -lc")
set(CMAKE_EXE_LINKER_FLAGS "-m elf_i386 -T ${PROJECT_SOURCE_DIR}/link.lds ${LIBS_FLAGS}")
set(CMAKE_C_LINK_EXECUTABLE "${LINKER_TOOL} <OBJECTS> ${CMAKE_EXE_LINKER_FLAGS} -o ${PROJECT_BINARY_DIR}/${PROJECT_NAME}.elf")

include_directories(
    ${PROJECT_SOURCE_DIR}/../applib/
)

file(GLOB C_LIST "*.c" "*.h" "*.S")
add_executable(${PROJECT_NAME} ${C_LIST})

# -S is used to strip the debug information and make the elf file smaller
add_custom_command(TARGET ${PROJECT_NAME}
                   POST_BUILD
                   COMMAND ${OBJCOPY_TOOL} -S ${PROJECT_NAME}.elf ${CMAKE_SOURCE_DIR}/../../image/${PROJECT_NAME}.elf
                   COMMAND ${OBJDUMP_TOOL} -x -d -S -m i386 ${PROJECT_BINARY_DIR}/${PROJECT_NAME}.elf > ${PROJECT_NAME}_dis.txt
                   COMMAND ${READELF_TOOL} -a ${PROJECT_BINARY_DIR}/${PROJECT_NAME}.elf > ${PROJECT_NAME}_elf.txt
)