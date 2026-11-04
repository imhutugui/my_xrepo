package("ecal")
    set_homepage("https://eclipse-ecal.github.io/ecal/")
    set_description("enhanced Communication Abstraction Layer, a high performance pub/sub and RPC middleware for robotics and automotive systems")
    set_license("Apache-2.0")

    -- The GitHub archive, because the 22 git submodules are not in it.
    add_urls("https://github.com/eclipse-ecal/ecal/archive/refs/tags/v$(version).tar.gz")
    -- github.com is the hop that stalls on this network, so its codeload target is offered as a
    -- fallback. The filename matters: this url ends in "v$(version)", so xmake would otherwise name
    -- the cached file ecal-$(version).1, and it only unpacks a cached file whose name carries an
    -- archive extension.
    add_urls("https://codeload.github.com/eclipse-ecal/ecal/tar.gz/refs/tags/v$(version)", {filename = "ecal.tar.gz"})

    add_versions("6.1.1", "fe084727ce0189f94454c7b57a86141b4ab4c311782c79cdee8996bfd73dc0ca")

    -- The four submodules eCAL's core build reaches for, at the commits the release tag pins.
    -- They are archives rather than git urls: xmake would otherwise also clone each repo's own
    -- submodules, which eCAL vendors separately. The .tar.gz suffix matters, because xmake only
    -- unpacks a downloaded resource when its file name has an archive extension.
    add_resources("6.1.1", "protozero",  "https://github.com/mapbox/protozero/archive/89a55ad2962cca3adbe8383a4b6d9a8411352ef2.tar.gz",      "e2b73677a09b57bcb17906a56d4c9ca119a45f66a3195fa1d6f101a8888ac2c7")
    add_resources("6.1.1", "recycle",    "https://github.com/steinwurf/recycle/archive/3f3d27ecdee87af9167adf1d2c2345ca2cbe1c94.tar.gz",      "c5227da34959120dac49aceba0a34d294d39a6f56ffbf93e10cb6fe98fd7635f")
    add_resources("6.1.1", "ecaludp",    "https://github.com/eclipse-ecal/ecaludp/archive/96e29b8cecfc56a627f7920d972930ebc62d1e79.tar.gz",    "aaea85d04fe288860ec05078b5ff5472d356ec42f2e15ae9882597b88842235c")
    add_resources("6.1.1", "tcp_pubsub", "https://github.com/eclipse-ecal/tcp_pubsub/archive/352e711b9ef10fec42ba7536bda244f43bf092cc.tar.gz", "984077107af61399b1d15698f47da17b2d88defbca0a6a2e4e58a6b7cd0acdde")

    -- Only the shared build is verified, so the static variant is not offered.
    add_configs("shared", {description = "Build shared library.", default = true, type = "boolean", readonly = true})

    add_configs("protobuf", {description = "Build the protobuf (de)serialization layer on top of eCAL core.", default = true, type = "boolean"})

    add_deps("cmake")
    -- Resolved from the packages instead of the submodules by eCAL's cmake dependency provider.
    add_deps("asio", "tclap", "yaml-cpp", {private = true})

    if is_plat("linux") then
        add_syslinks("pthread", "rt", "dl")
    end

    on_load(function (package)
        -- ecal_core itself never refers to protobuf; only ecal_core_pb and ecal_protobuf_base do,
        -- and they leave protobuf symbols undefined for the consumer to resolve.
        if package:config("protobuf") then
            -- Protobuf made Descriptor::name() and friends return absl::string_view from 29 onward
            -- (port_def.inc defines PROTOBUF_FUTURE_STRING_VIEW_RETURN_TYPE unconditionally), while
            -- eCAL 6.1.1 assigns those names to std::string, so only the 28 line still compiles.
            -- It also has to come from a repository: the system protobuf here is 3.6.1, which is old
            -- enough to compile but nothing like what the consumer ends up linking.
            local protobuf = "protobuf-cpp <29"
            package:add("deps", protobuf)
            package:extraconf_set("deps", protobuf, "system", false)
        end
    end)

    on_install("linux", function (package)
        -- The directories already exist in the archive with only their cmake wrappers, so each
        -- submodule tree is filled in where eCAL's build-*.cmake expects it. The resource is
        -- extracted under a single <repo>-<commit> folder, which archive.extract keeps.
        for _, name in ipairs({"protozero", "recycle", "ecaludp", "tcp_pubsub"}) do
            local dir = path.join("thirdparty", name, name)
            if not os.isfile(path.join(dir, "CMakeLists.txt")) then
                os.tryrm(dir)
                os.cp(os.dirs(path.join(package:resourcedir(name), "*"))[1], dir)
            end
        end

        -- Every find_package() inside the tree goes through this provider; without it the bundled
        -- dependencies are never wired up and the configure fails.
        local configs = {
            "-DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=" .. path.absolute("cmake/submodule_dependencies.cmake"),
            "-DECAL_THIRDPARTY_BUILD_ASIO=OFF",
            "-DECAL_THIRDPARTY_BUILD_TCLAP=OFF",
            "-DECAL_THIRDPARTY_BUILD_YAML-CPP=OFF",
            -- the release archive is not a git tree, so eCAL would otherwise configure version 0.0.0
            "-DECAL_BUILD_VERSION=" .. package:version(),
            "-DBUILD_SHARED_LIBS=ON",
            -- applications, bindings and the record/playback toolchain are not library dependencies
            "-DECAL_BUILD_APPS=OFF",
            "-DECAL_BUILD_APP_SDK=OFF",
            "-DECAL_BUILD_SAMPLES=OFF",
            "-DECAL_BUILD_TESTS=OFF",
            "-DECAL_BUILD_DOCS=OFF",
            "-DECAL_BUILD_TIMEPLUGINS=OFF",
            "-DECAL_BUILD_C_BINDING=OFF",
            "-DECAL_INSTALL_SAMPLE_SOURCES=OFF",
            "-DECAL_USE_QT=OFF",
            "-DECAL_USE_HDF5=OFF",
            "-DECAL_USE_CURL=OFF",
            "-DECAL_USE_FTXUI=OFF",
        }
        if package:config("protobuf") then
            -- The pbftags plugin is written against the protobuf 3.11 API eCAL vendors (it uses
            -- FieldDescriptor::label() and the two-argument io::Printer), which even the pinned
            -- protobuf no longer offers the same way. eCAL's SDK build path is to keep the
            -- generated *.pbftags.h in the tree, and they are in this archive next to the protozero
            -- serializers, so regeneration is switched off. Upstream sets the variable
            -- unconditionally from CMAKE_CROSSCOMPILING, so it has to be neutralised for -D to work.
            io.replace("CMakeLists.txt", "set%(ECAL_CORE_GENERATE_PBFTAGS%s+ON%)", "")
            table.insert(configs, "-DECAL_CORE_GENERATE_PBFTAGS=OFF")
            table.insert(configs, "-DECAL_THIRDPARTY_BUILD_PROTOBUF=OFF")
            -- cmake's module-mode FindProtobuf exports an interface without abseil and without the
            -- C++17 requirement that protobuf's headers need, so only the config package works.
            -- Abseil is located explicitly because protobuf's config resolves it as a package, not
            -- a path, and reusing protobuf-cpp's own abseil avoids pulling in a second version.
            table.insert(configs, "-DCMAKE_FIND_PACKAGE_PREFER_CONFIG=ON")
            local abseil = package:dep("protobuf-cpp"):dep("abseil")
            table.insert(configs, "-Dabsl_DIR=" .. path.join(abseil:installdir(), "lib", "cmake", "absl"))
        else
            table.insert(configs, "-DECAL_USE_PROTOBUF=OFF")
        end
        import("package.tools.cmake").install(package, configs)
    end)

    on_test(function (package)
        assert(package:check_cxxsnippets({test = [[
            #include <ecal/ecal.h>
            void test() {
                auto version = eCAL::GetVersionString();
                (void)version;
            }
        ]]}, {configs = {languages = "c++17"}}))
        if package:config("protobuf") then
            assert(package:check_cxxsnippets({test = [[
                #include <ecal/msg/protobuf/publisher.h>
                #include <google/protobuf/any.pb.h>
                void test() {
                    eCAL::protobuf::CPublisher<google::protobuf::Any> publisher("ecal-xmake-test");
                    (void)publisher;
                }
            ]]}, {configs = {languages = "c++17"}}))
        end
    end)
package_end()
