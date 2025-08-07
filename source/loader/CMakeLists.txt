
project(loader LANGUAGES C)

# customized linker
set(CMAKE_EXE_LINKER_FLAGS "-m elf_i386  -Ttext=0x8000") # compiled address starts at 0x8000
set(CMAKE_C_LINK_EXECUTABLE "${LINKER_TOOL} <OBJECTS> ${CMAKE_EXE_LINKER_FLAGS} -o ${PROJECT_BINARY_DIR}/${PROJECT_NAME}.elf")

# make sure start.S is at the beginning so that jumping to 0x7c00 can begin with _start in start.S
file(GLOB C_LIST "*.c" "*.h")
add_executable(${PROJECT_NAME} start.S ${C_LIST})

# note that boot and loader are converted into bin files whereas kernel is in elf format
add_custom_command(TARGET ${PROJECT_NAME}
                   POST_BUILD
                   # use objcopy tool to turn .elf file into .bin file
                   COMMAND ${OBJCOPY_TOOL} -O binary ${PROJECT_NAME}.elf ${CMAKE_SOURCE_DIR}/../../image/${PROJECT_NAME}.bin
                   COMMAND ${OBJDUMP_TOOL} -x -d -S -m i8086 ${PROJECT_BINARY_DIR}/${PROJECT_NAME}.elf > ${PROJECT_NAME}_dis.txt
                   COMMAND ${READELF_TOOL} -a ${PROJECT_BINARY_DIR}/${PROJECT_NAME}.elf > ${PROJECT_NAME}_elf.txt
)