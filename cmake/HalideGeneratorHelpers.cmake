cmake_minimum_required(VERSION 3.14)

# TODO: find a use for these, or remove them?
define_property(TARGET PROPERTY HL_GEN_TARGET
                BRIEF_DOCS "On a Halide library target, names the generator target used to create it"
                FULL_DOCS "On a Halide library target, names the generator target used to create it")

define_property(TARGET PROPERTY HL_FILTER_NAME
                BRIEF_DOCS "On a Halide library target, names the filter this library corresponds to"
                FULL_DOCS "On a Halide library target, names the filter this library corresponds to")

define_property(TARGET PROPERTY HL_LIBNAME
                BRIEF_DOCS "On a Halide library target, names the function it provides"
                FULL_DOCS "On a Halide library target, names the function it provides")

define_property(TARGET PROPERTY HL_RUNTIME
                BRIEF_DOCS "On a Halide library target, names the runtime target it depends on"
                FULL_DOCS "On a Halide library target, names the runtime target it depends on")

define_property(TARGET PROPERTY HL_PARAMS
                BRIEF_DOCS "On a Halide library target, lists the parameters used to configure the filter"
                FULL_DOCS "On a Halide library target, lists the parameters used to configure the filter")

define_property(TARGET PROPERTY HL_TARGETS
                BRIEF_DOCS "On a Halide library target, lists the runtime targets supported by the filter"
                FULL_DOCS "On a Halide library target, lists the runtime targets supported by the filter")

define_property(TARGET PROPERTY HLRT_TARGETS
                BRIEF_DOCS "On a Halide runtime target, lists the targets the runtime backs"
                FULL_DOCS "On a Halide runtime target, lists the targets the runtime backs")

function(add_halide_library TARGET)
    set(options GRADIENT_DESCENT C_BACKEND)
    set(oneValueArgs FROM GENERATOR FUNCTION_NAME USE_RUNTIME PYTHON_EXTENSION SCHEDULER REGISTRATION)
    set(multiValueArgs PARAMS TARGETS FEATURES PLUGINS)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if (NOT ARG_FROM)
        message(FATAL_ERROR "Missing FROM argument specifying a Halide generator target")
    endif ()

    if (ARG_GRADIENT_DESCENT)
        set(GRADIENT_DESCENT 1)
    else ()
        set(GRADIENT_DESCENT 0)
    endif ()

    if (NOT ARG_GENERATOR)
        set(ARG_GENERATOR "${TARGET}")
    endif ()

    if (NOT ARG_FUNCTION_NAME)
        set(ARG_FUNCTION_NAME "${TARGET}")
    endif ()

    if (NOT ARG_TARGETS)
        set(ARG_TARGETS host)
    endif ()

    set(generatorCommand ${ARG_FROM})
    if (WIN32)
        set(generatorCommand ${CMAKE_COMMAND} -E env "PATH=$<SHELL_PATH:$<TARGET_FILE_DIR:Halide::Halide>>" "$<TARGET_FILE:${ARG_FROM}>")
    endif ()

    unset(EXTRA_RT_LIBS)
    if (opengl IN_LIST ARG_FEATURES)
        if (NOT TARGET X11::X11)
            message(AUTHOR_WARNING "OpenGL with Halide requires target X11::X11. Attempting to find_package(X11) and create target X11::X11.")

            find_package(X11 QUIET REQUIRED)
            add_library(Halide_Generator_Helpers_X11 INTERFACE)
            add_library(X11::X11 ALIAS Halide_Generator_Helpers_X11)
            target_link_libraries(Halide_Generator_Helpers_X11 INTERFACE ${X11_LIBRARIES})
            target_include_directories(Halide_Generator_Helpers_X11 INTERFACE ${X11_INCLUDE_DIR})
        endif ()

        if (NOT TARGET OpenGL::GL)
            message(AUTHOR_WARNING "OpenGL with Halide requires target OpenGL::GL. Attempting to find_package(OpenGL).")
            find_package(OpenGL QUIET REQUIRED)
        endif ()

        set(EXTRA_RT_LIBS OpenGL::GL X11::X11)
    endif ()

    unset(TARGETS)
    foreach (T IN LISTS ARG_TARGETS)
        if ("${T}" STREQUAL "")
            set(T host)
        endif ()
        foreach (F IN LISTS ARG_FEATURES)
            set(T "${T}-${F}")
        endforeach ()
        list(APPEND TARGETS "${T}-no_runtime")
    endforeach ()
    string(REPLACE ";" "," TARGETS "${TARGETS}")

    if (ARG_C_BACKEND AND ARG_USE_RUNTIME)
        message(WARNING "Warning: the C backend does not use a runtime.")
    endif ()

    if (NOT ARG_C_BACKEND)
        if (NOT ARG_USE_RUNTIME)
            add_library("${TARGET}.runtime" STATIC IMPORTED)
            target_link_libraries("${TARGET}.runtime"
                                  INTERFACE
                                  Threads::Threads
                                  ${CMAKE_DL_LIBS}
                                  ${EXTRA_RT_LIBS})

            set_target_properties("${TARGET}.runtime"
                                  PROPERTIES
                                  IMPORTED_LOCATION "${CMAKE_CURRENT_BINARY_DIR}/${TARGET}.runtime${CMAKE_STATIC_LIBRARY_SUFFIX}")

            add_custom_command(OUTPUT "${TARGET}.runtime${CMAKE_STATIC_LIBRARY_SUFFIX}"
                               COMMAND ${generatorCommand} -r "${TARGET}.runtime" -o . target=$<JOIN:$<TARGET_PROPERTY:${TARGET}.runtime,HLRT_TARGETS>,$<COMMA>>
                               DEPENDS "${ARG_FROM}")

            add_custom_target("${TARGET}.runtime.update"
                              DEPENDS "${TARGET}.runtime${CMAKE_STATIC_LIBRARY_SUFFIX}")

            add_dependencies("${TARGET}.runtime" "${TARGET}.runtime.update")
            set(ARG_USE_RUNTIME "${TARGET}.runtime")
        endif ()

        if (NOT TARGET ${ARG_USE_RUNTIME})
            message(FATAL_ERROR "Invalid runtime target ${ARG_USE_RUNTIME}")
        endif ()

        # Add in the runtime targets but first remove features that should not be attached to a runtime
        # TODO: The fact that profile being here fixes a linker error on Windows smells like a bug.
        #       It complains about a symbol being duplicated between the runtime and the object.
        set(RT_TARGETS ${TARGETS})
        foreach (T IN ITEMS user_context no_asserts no_bounds_query no_runtime profile)
            string(REPLACE "-${T}" "" RT_TARGETS "${RT_TARGETS}")
        endforeach ()

        set_property(TARGET "${ARG_USE_RUNTIME}" APPEND PROPERTY HLRT_TARGETS "${RT_TARGETS}")
    else ()
        # The C backend does not provide a runtime.
        unset(ARG_USE_RUNTIME)
    endif ()

    ##
    # Handle extra outputs
    ##

    set(GENERATOR_OUTPUTS c_header)
    set(GENERATOR_OUTPUT_FILES "${TARGET}.h")

    if (ARG_C_BACKEND)
        list(APPEND GENERATOR_OUTPUTS c_source)
        list(APPEND GENERATOR_OUTPUT_FILES "${TARGET}.halide_generated.cpp")
    else ()
        list(APPEND GENERATOR_OUTPUTS static_library)
        list(APPEND GENERATOR_OUTPUT_FILES "${TARGET}${CMAKE_STATIC_LIBRARY_SUFFIX}")
    endif ()

    if (ARG_PYTHON_EXTENSION)
        set(${ARG_PYTHON_EXTENSION} "${TARGET}.py.cpp" PARENT_SCOPE)
        list(APPEND GENERATOR_OUTPUT_FILES "${TARGET}.py.cpp")
        list(APPEND GENERATOR_OUTPUTS python_extension)
    endif ()

    if (ARG_REGISTRATION)
        set(${ARG_REGISTRATION} "${TARGET}.registration.cpp" PARENT_SCOPE)
        list(APPEND GENERATOR_OUTPUT_FILES "${TARGET}.registration.cpp")
        list(APPEND GENERATOR_OUTPUTS registration)
    endif ()

    unset(GEN_SCHEDULER)
    if (ARG_SCHEDULER)
        set(GEN_SCHEDULER -s ${ARG_SCHEDULER})
    endif ()

    ##
    # Main library target for filter.
    ##

    if (ARG_C_BACKEND)
        add_library("${TARGET}" STATIC "${TARGET}.halide_generated.cpp")
    else ()
        add_library("${TARGET}" STATIC IMPORTED)
    endif ()

    # load the plugins and setup dependencies
    unset(GEN_PLUGINS)
    if (ARG_PLUGINS)
        add_dependencies("${TARGET}" ${ARG_PLUGINS})
        foreach (P IN LISTS ARG_PLUGINS)
            list(APPEND GEN_PLUGINS "$<TARGET_FILE:${P}>")
        endforeach ()
        set(GEN_PLUGINS -p ${GEN_PLUGINS})
    endif ()

    set_target_properties("${TARGET}" PROPERTIES
                          HL_GEN_TARGET "${ARG_FROM}"
                          HL_FILTER_NAME "${ARG_GENERATOR}"
                          HL_LIBNAME "${ARG_FUNCTION_NAME}"
                          HL_PARAMS "${ARG_PARAMS}"
                          HL_TARGETS "${TARGETS}")

    add_custom_command(OUTPUT ${GENERATOR_OUTPUT_FILES}
                       COMMAND ${generatorCommand}
                       -n "${TARGET}"
                       -d "${GRADIENT_DESCENT}"
                       -g "${ARG_GENERATOR}"
                       -f "${ARG_FUNCTION_NAME}"
                       -e "$<JOIN:${GENERATOR_OUTPUTS},$<COMMA>>"
                       ${GEN_PLUGINS}
                       ${GEN_SCHEDULER}
                       -o .
                       "target=${TARGETS}"
                       ${ARG_PARAMS}
                       DEPENDS "${ARG_FROM}")

    list(TRANSFORM GENERATOR_OUTPUT_FILES PREPEND "${CMAKE_CURRENT_BINARY_DIR}/")
    add_custom_target("${TARGET}.update" DEPENDS ${GENERATOR_OUTPUT_FILES})

    if (NOT ARG_C_BACKEND)
        set_target_properties("${TARGET}" PROPERTIES IMPORTED_LOCATION "${CMAKE_CURRENT_BINARY_DIR}/${TARGET}${CMAKE_STATIC_LIBRARY_SUFFIX}")
    endif ()

    add_dependencies("${TARGET}" "${TARGET}.update")

    target_include_directories("${TARGET}" INTERFACE "${CMAKE_CURRENT_BINARY_DIR}")
    target_link_libraries("${TARGET}" INTERFACE "${ARG_USE_RUNTIME}")
endfunction()