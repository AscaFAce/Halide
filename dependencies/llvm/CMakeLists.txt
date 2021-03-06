##
# Find LLVM and check the version.
##

find_package(LLVM ${HALIDE_REQUIRE_LLVM_VERSION} REQUIRED)
message(STATUS "Found LLVM ${LLVM_PACKAGE_VERSION}")
message(STATUS "Using LLVMConfig.cmake in: ${LLVM_DIR}")

if ("${LLVM_PACKAGE_VERSION}" VERSION_LESS 9.0)
    message(FATAL_ERROR "LLVM version must be 9.0 or newer")
endif ()

if ("${LLVM_PACKAGE_VERSION}" VERSION_GREATER 11.0)
    message(WARNING "Halide is not tested on LLVM versions beyond 11.0")
endif ()

##
# Promote executable targets from LLVM
##

set_target_properties(llvm-as PROPERTIES IMPORTED_GLOBAL TRUE)
set_target_properties(llvm-nm PROPERTIES IMPORTED_GLOBAL TRUE)
set_target_properties(llvm-config PROPERTIES IMPORTED_GLOBAL TRUE)

##
# Create target for holding LLVM properties
##

add_library(Halide_LLVM INTERFACE)
add_library(Halide::LLVM ALIAS Halide_LLVM)

set_target_properties(Halide_LLVM PROPERTIES EXPORT_NAME LLVM)

target_include_directories(Halide_LLVM INTERFACE $<BUILD_INTERFACE:${LLVM_INCLUDE_DIRS}>)
target_compile_definitions(Halide_LLVM INTERFACE
                           "LLVM_VERSION=${LLVM_VERSION_MAJOR}${LLVM_VERSION_MINOR}"
                           ${LLVM_DEFINITIONS})

option(HALIDE_ENABLE_EXCEPTIONS "Enable exceptions" ${LLVM_ENABLE_EH})
if (HALIDE_ENABLE_EXCEPTIONS)
    target_compile_definitions(Halide_LLVM INTERFACE WITH_EXCEPTIONS)
endif ()

##
# Detect supported llvm targets
##

function(check_llvm_target TARGET HAS_TARGET)
    if ("${TARGET}" IN_LIST LLVM_TARGETS_TO_BUILD)
        set(${HAS_TARGET} ON PARENT_SCOPE)
    else ()
        set(${HAS_TARGET} OFF PARENT_SCOPE)
    endif ()
endfunction()

check_llvm_target(X86 WITH_X86)
check_llvm_target(ARM WITH_ARM)
check_llvm_target(AArch64 WITH_AARCH64)
check_llvm_target(Hexagon WITH_HEXAGON)
check_llvm_target(Mips WITH_MIPS)
check_llvm_target(PowerPC WITH_POWERPC)
check_llvm_target(NVPTX WITH_NVPTX)
check_llvm_target(RISCV WITH_RISCV)
check_llvm_target(AMDGPU WITH_AMDGPU)

##
# Create options that are initialized based on LLVM's config
##

set(LLVM_COMPONENTS mcjit bitwriter linker passes)

option(TARGET_X86 "Include x86 target" ${WITH_X86})
if (TARGET_X86)
    target_compile_definitions(Halide_LLVM INTERFACE WITH_X86)
    list(APPEND LLVM_COMPONENTS X86)
endif ()

option(TARGET_ARM "Include ARM target" ${WITH_ARM})
if (TARGET_ARM)
    target_compile_definitions(Halide_LLVM INTERFACE WITH_ARM)
    list(APPEND LLVM_COMPONENTS ARM)
endif ()

option(TARGET_AARCH64 "Include AARCH64 (arm64) target" ${WITH_AARCH64})
if (TARGET_AARCH64)
    target_compile_definitions(Halide_LLVM INTERFACE WITH_AARCH64)
    list(APPEND LLVM_COMPONENTS AArch64)
endif ()

option(TARGET_HEXAGON "Include Hexagon target" ${WITH_HEXAGON})
if (TARGET_HEXAGON)
    target_compile_definitions(Halide_LLVM INTERFACE WITH_HEXAGON)
    list(APPEND LLVM_COMPONENTS Hexagon)
endif ()

option(TARGET_MIPS "Include MIPS target" ${WITH_MIPS})
if (TARGET_MIPS)
    target_compile_definitions(Halide_LLVM INTERFACE WITH_MIPS)
    list(APPEND LLVM_COMPONENTS Mips)
endif ()

option(TARGET_POWERPC "Include POWERPC target" ${WITH_POWERPC})
if (TARGET_POWERPC)
    target_compile_definitions(Halide_LLVM INTERFACE WITH_POWERPC)
    list(APPEND LLVM_COMPONENTS PowerPC)
endif ()

if (TARGET_WEBASSEMBLY)
    target_compile_definitions(Halide_LLVM INTERFACE WITH_WEBASSEMBLY)
    list(APPEND LLVM_COMPONENTS WebAssembly)
endif ()

option(TARGET_PTX "Include PTX target" ${WITH_NVPTX})
if (TARGET_PTX)
    target_compile_definitions(Halide_LLVM INTERFACE WITH_PTX)
    list(APPEND LLVM_COMPONENTS NVPTX)
endif ()

option(TARGET_AMDGPU "Include AMDGPU target" ${WITH_AMDGPU})
if (TARGET_AMDGPU)
    target_compile_definitions(Halide_LLVM INTERFACE WITH_AMDGPU)
    list(APPEND LLVM_COMPONENTS AMDGPU)
endif ()

option(TARGET_RISCV "Include RISCV target" ${WITH_RISCV})
if (TARGET_RISCV)
    target_compile_definitions(Halide_LLVM INTERFACE WITH_RISCV)
    list(APPEND LLVM_COMPONENTS RISCV)
endif ()

##
# Finish setting up llvm library
##

if (LLVM_USE_SHARED_LLVM_LIBRARY)
    set(LLVM_USE_SHARED "USE_SHARED")
endif ()

llvm_map_components_to_libnames(LLVM_LIBNAMES ${LLVM_COMPONENTS})
target_link_libraries(Halide_LLVM INTERFACE ${LLVM_LIBNAMES})

option(HALIDE_ENABLE_RTTI "Enable RTTI" ${LLVM_ENABLE_RTTI})
if (HALIDE_ENABLE_RTTI AND NOT LLVM_ENABLE_RTTI)
    message(FATAL_ERROR "Can't enable RTTI. LLVM was compiled without it")
endif ()

if (NOT LLVM_ENABLE_RTTI)
    message(STATUS "LLVM built with RTTI disabled. Adding to interface requirements.")
    target_compile_options(Halide_LLVM INTERFACE
                           $<$<COMPILE_LANG_AND_ID:CXX,MSVC>:/GR->
                           $<$<AND:$<COMPILE_LANGUAGE:CXX>,$<NOT:$<CXX_COMPILER_ID:MSVC>>>:-fno-rtti>)
endif ()

if (LLVM_LIBCXX GREATER -1)
    message(STATUS "LLVM linked to libc++. Adding to interface requirements.")
    target_compile_options(Halide_LLVM INTERFACE $<$<STREQUAL:$<TARGET_PROPERTY:LINKER_LANGUAGE>,CXX>:-stdlib=libc++>)
    target_link_options(Halide_LLVM INTERFACE $<$<STREQUAL:$<TARGET_PROPERTY:LINKER_LANGUAGE>,CXX>:-stdlib=libc++>)
endif ()

# When building the Halide library as a static library, we have to expose
# our LLVM dependencies so that CMake has the information it needs for the
# installed package. When building it as a shared library, LLVM becomes a
# fully private implementation detail as far as CMake is concerned, so it
# then doesn't need to expose any LLVM-related dependencies through targets.
if (NOT BUILD_SHARED_LIBS)
    install(TARGETS Halide_LLVM
            EXPORT Halide_Targets)
endif ()
