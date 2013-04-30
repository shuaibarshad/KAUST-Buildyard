
# Copyright (c) 2012 Stefan Eilemann <Stefan.Eilemann@epfl.ch>

function(USE_EXTERNAL_GATHER_DEBS NAME)
  # sets ${NAME}_DEBS from all dependencies on return
  set(DEBS)
  set(DEPENDS)
  set(${UPPER_NAME}_DEBS)

  # recurse to get dependency roots
  foreach(proj ${${NAME}_DEPENDS})
    string(TOUPPER ${proj} PROJ)
    use_external_gather_debs(${PROJ})
    list(APPEND DEBS ${${PROJ}_DEBS})
  endforeach()

  list(APPEND DEBS ${${NAME}_DEB_DEPENDS})
  if(DEBS)
    list(REMOVE_DUPLICATES DEBS)
    list(SORT DEBS)
    set(${NAME}_DEBS ${DEBS} PARENT_SCOPE) # return value
  endif()
endfunction()

# write in-source FindPackages.cmake, .travis.yml
function(USE_EXTERNAL_DEPS name)
  string(TOUPPER ${name} NAME)
  if(${NAME}_SKIPFIND OR NOT ${NAME}_DEPENDS)
    return()
  endif()

  set(_fpIn "${CMAKE_CURRENT_BINARY_DIR}/${name}FindPackages.cmake")
  set(_fpOut "${${NAME}_SOURCE}/CMake/FindPackages.cmake")
  set(_ciIn "${CMAKE_CURRENT_BINARY_DIR}/${name}Travis.yml")
  set(_ciOut "${${NAME}_SOURCE}/.travis.yml")
  set(_scriptdir ${CMAKE_CURRENT_BINARY_DIR}/${name})
  set(DEPMODE)

  set(_deps)
  file(WRITE ${_fpIn}
    "# generated by Buildyard, do not edit.\n\n"
    "include(System)\n"
    "list(APPEND FIND_PACKAGES_DEFINES \${SYSTEM})\n\n")
  file(WRITE ${_ciIn}
    "# generated by Buildyard, do not edit.\n"
    "before_install:\n"
    " - sudo apt-get update -qq\n"
    " - sudo apt-get install -qq ")

  foreach(_dep ${${NAME}_DEPENDS})
    if(${_dep} STREQUAL "OPTIONAL")
      set(DEPMODE)
    elseif(${_dep} STREQUAL "REQUIRED")
      set(DEPMODE " REQUIRED")
    else()
      string(TOUPPER ${_dep} _DEP)
      set(COMPONENTS)
      if(${NAME}_${_DEP}_COMPONENTS)
        if(DEPMODE)
          set(COMPONENTS " ${${NAME}_${_DEP}_COMPONENTS}")
        else()
          set(COMPONENTS " COMPONENTS ${${NAME}_${_DEP}_COMPONENTS}")
        endif()
      endif()
      if(${_DEP}_CMAKE_INCLUDE)
        set(${_DEP}_CMAKE_INCLUDE "${${_DEP}_CMAKE_INCLUDE} ")
      endif()
      if(NOT ${_DEP}_SKIPFIND)
        list(APPEND _deps ${_dep})
        set(DEFDEP "${NAME}_USE_${_DEP}")
        string(REGEX REPLACE "-" "_" DEFDEP ${DEFDEP})
        file(APPEND ${_fpIn}
          "find_package(${_dep} ${${_DEP}_PACKAGE_VERSION}${DEPMODE}${COMPONENTS})\n"
          "if(${_dep}_FOUND)\n"
          "  set(${_dep}_name ${_dep})\n"
          "endif()\n"
          "if(${_DEP}_FOUND)\n"
          "  set(${_dep}_name ${_DEP})\n"
          "endif()\n"
          "if(${_dep}_name)\n"
          "  list(APPEND FIND_PACKAGES_DEFINES ${DEFDEP})\n"
          "  link_directories(\${\${${_dep}_name}_LIBRARY_DIRS})\n"
          "  if(NOT \"${${_DEP}_CMAKE_INCLUDE}\${\${${_dep}_name}_INCLUDE_DIRS}\" MATCHES \"-NOTFOUND\")\n"
          "    include_directories(${${_DEP}_CMAKE_INCLUDE}\${\${${_dep}_name}_INCLUDE_DIRS})\n"
          "  endif()\n"
          "endif()\n\n"
          )
      endif()
    endif()
  endforeach()

  use_external_gather_debs(${NAME})
  foreach(_dep ${${NAME}_DEBS})
    file(APPEND ${_ciIn} "${_dep} ")
  endforeach()

  file(APPEND ${_fpIn} "\n"
    "set(${NAME}_DEPENDS ${_deps})\n\n"
    "# Write defines.h and options.cmake\n"
    "if(NOT PROJECT_INCLUDE_NAME)\n"
    "  set(PROJECT_INCLUDE_NAME \${CMAKE_PROJECT_NAME})\n"
    "endif()\n"
    "if(NOT OPTIONS_CMAKE)\n"
    "  set(OPTIONS_CMAKE \${CMAKE_BINARY_DIR}/options.cmake)\n"
    "endif()\n"
    "set(DEFINES_FILE \"\${CMAKE_BINARY_DIR}/include/\${PROJECT_INCLUDE_NAME}/defines\${SYSTEM}.h\")\n"
    "set(DEFINES_FILE_IN \${DEFINES_FILE}.in)\n"
    "file(WRITE \${DEFINES_FILE_IN}\n"
    "  \"// generated by Buildyard, do not edit.\\n\\n\"\n"
    "  \"#ifndef \${CMAKE_PROJECT_NAME}_DEFINES_\${SYSTEM}_H\\n\"\n"
    "  \"#define \${CMAKE_PROJECT_NAME}_DEFINES_\${SYSTEM}_H\\n\\n\")\n"
    "file(WRITE \${OPTIONS_CMAKE} \"# Optional modules enabled during build\\n\")\n"
    "foreach(DEF \${FIND_PACKAGES_DEFINES})\n"
    "  add_definitions(-D\${DEF})\n"
    "  file(APPEND \${DEFINES_FILE_IN}\n"
    "  \"#ifndef \${DEF}\\n\"\n"
    "  \"#  define \${DEF}\\n\"\n"
    "  \"#endif\\n\")\n"
    "if(NOT DEF STREQUAL SYSTEM)\n"
    "  file(APPEND \${OPTIONS_CMAKE} \"set(\${DEF} ON)\\n\")\n"
    "endif()\n"
    "endforeach()\n"
    "file(APPEND \${DEFINES_FILE_IN}\n"
    "  \"\\n#endif\\n\")\n\n"
    "include(UpdateFile)\n"
    "update_file(\${DEFINES_FILE_IN} \${DEFINES_FILE})\n"
    )
  file(APPEND ${_ciIn} "\n"
    "language: cpp\n"
    "script:\n"
    " - git clone --depth 10 https://github.com/Eyescale/Buildyard.git\n"
    " - cd Buildyard\n"
    " - git clone --depth 10 ${${BY_CURRENT_CONFIGGROUP}_CONFIGURL} config.${BY_CURRENT_CONFIGGROUP}\n"
    " - make -j8 ${name}-test ARGS=-V\n")

  file(WRITE ${_scriptdir}/writeDeps.cmake
    "list(APPEND CMAKE_MODULE_PATH ${CMAKE_SOURCE_DIR}/CMake)\n"
    "include(UpdateFile)\n"
    "update_file(${_fpIn} ${_fpOut})\n"
    "update_file(${_ciIn} ${_ciOut})\n")

  setup_scm(${name})
  ExternalProject_Add_Step(${name} rmFindPackages
    COMMENT "Resetting FindPackages"
    COMMAND ${SCM_RESET} CMake/FindPackages.cmake || ${CMAKE_COMMAND} -E remove CMake/FindPackages.cmake
    WORKING_DIRECTORY "${${NAME}_SOURCE}"
    DEPENDEES mkdir DEPENDERS download ALWAYS 1
    )
  ExternalProject_Add_Step(${name} rmTravis
    COMMENT "Resetting travis.yml"
    COMMAND ${SCM_RESET} .travis.yml || ${CMAKE_COMMAND} -E remove .travis.yml
    WORKING_DIRECTORY "${${NAME}_SOURCE}"
    DEPENDEES mkdir DEPENDERS download ALWAYS 1
    )

  ExternalProject_Add_Step(${name} FindPackages
    COMMENT "Updating ${_fpOut}, ${_ciOut}"
    COMMAND ${CMAKE_COMMAND} -DBUILDYARD:PATH=${CMAKE_SOURCE_DIR}
            -P ${_scriptdir}/writeDeps.cmake
    DEPENDEES update DEPENDERS configure DEPENDS ${${NAME}_CONFIGFILE}
    )
endfunction()
