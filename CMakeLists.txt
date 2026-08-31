cmake_minimum_required(VERSION 3.16)
project(Blinker VERSION 1.0.0 LANGUAGES C)

add_executable(blinker-as assembler/blinker-as.c)
target_compile_features(blinker-as PRIVATE c_std_11)
set_target_properties(blinker-as PROPERTIES C_EXTENSIONS OFF)
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(blinker-as PRIVATE -Wall -Wextra -Wpedantic)
endif()

set(EXAMPLE_IMAGES)
foreach(example arithmetic macros memory)
    set(image "${CMAKE_CURRENT_BINARY_DIR}/${example}.hex")
    add_custom_command(OUTPUT "${image}"
        COMMAND $<TARGET_FILE:blinker-as> "${CMAKE_CURRENT_SOURCE_DIR}/examples/${example}.asm" -o "${image}"
        DEPENDS blinker-as "${CMAKE_CURRENT_SOURCE_DIR}/examples/${example}.asm"
        VERBATIM)
    list(APPEND EXAMPLE_IMAGES "${image}")
endforeach()
add_custom_target(examples DEPENDS ${EXAMPLE_IMAGES})

find_program(IVERILOG_EXECUTABLE iverilog)
find_program(VVP_EXECUTABLE vvp)
if(IVERILOG_EXECUTABLE)
    set(RTL_SOURCES blinker.sv instruction_decoder.sv memory.sv fetch.sv alfpu.sv reg_file.sv stage_registers.sv)
    foreach(bench br_tb brgt_tb call_tb program_tb)
        if(bench STREQUAL "program_tb")
            set(bench_source "${CMAKE_CURRENT_SOURCE_DIR}/sim/program_tb.sv")
        else()
            set(bench_source "${CMAKE_CURRENT_SOURCE_DIR}/${bench}.sv")
        endif()
        add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/${bench}.out"
            COMMAND "${IVERILOG_EXECUTABLE}" -g2012 -I "${CMAKE_CURRENT_SOURCE_DIR}"
                -s "${bench}" -o "${CMAKE_CURRENT_BINARY_DIR}/${bench}.out" "${bench_source}"
            DEPENDS "${bench_source}" ${RTL_SOURCES}
            VERBATIM)
        add_custom_target(${bench} DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/${bench}.out")
    endforeach()
    add_custom_target(rtl)
    add_dependencies(rtl br_tb brgt_tb call_tb program_tb)
    add_custom_command(OUTPUT "${CMAKE_CURRENT_BINARY_DIR}/dual_execute.out"
        COMMAND "${IVERILOG_EXECUTABLE}" -g2012 -s dual_execute
            -o "${CMAKE_CURRENT_BINARY_DIR}/dual_execute.out"
            "${CMAKE_CURRENT_SOURCE_DIR}/extensions/dual_execute.sv"
        DEPENDS extensions/dual_execute.sv VERBATIM)
    add_custom_target(dual-execute DEPENDS "${CMAKE_CURRENT_BINARY_DIR}/dual_execute.out")
else()
    message(STATUS "Icarus Verilog not found: assembler targets remain available")
endif()

install(TARGETS blinker-as RUNTIME DESTINATION bin)
