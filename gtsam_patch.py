import os, sys

src = sys.argv[1]
print(f"Patching source dir: {src}")

# Patch 1: CMakeLists.txt
cmake_f = os.path.join(src, "CMakeLists.txt")
if os.path.exists(cmake_f):
    with open(cmake_f, "r") as f:
        cl = f.read()
    if "_USE_MATH_DEFINES" not in cl:
        idx = cl.find("add_library(gtsam_points SHARED")
        if idx >= 0:
            depth = 0
            j = idx
            while j < len(cl):
                if cl[j] == "(":
                    depth += 1
                elif cl[j] == ")":
                    depth -= 1
                    if depth == 0:
                        pos = j + 1
                        ins = "\ntarget_compile_definitions(gtsam_points PRIVATE _USE_MATH_DEFINES)\ntarget_compile_options(gtsam_points PRIVATE /DNOMINMAX)\n"
                        cl = cl[:pos] + ins + cl[pos:]
                        break
                j += 1
            with open(cmake_f, "w") as f:
                f.write(cl)
            print("PATCHED CMakeLists.txt")

# Patch 2: M_PI in header files
for rel in ["include/gtsam_points/segmentation/region_growing.hpp",
            "include/gtsam_points/registration/ransac.hpp",
            "include/gtsam_points/segmentation/min_cut.hpp"]:
    fp = os.path.join(src, rel)
    if os.path.exists(fp):
        with open(fp, "r") as f:
            c = f.read()
        if "#pragma once" in c and "ifndef M_PI" not in c:
            c = c.replace("#pragma once", "#pragma once\n#ifndef M_PI\n#define M_PI 3.14159265358979323846\n#endif\n")
            with open(fp, "w") as f:
                f.write(c)
            print(f"PATCHED M_PI: {os.path.basename(rel)}")

# Patch 3: fpfh_estimation.cpp
fpfh = os.path.join(src, "src/gtsam_points/features/fpfh_estimation.cpp")
if os.path.exists(fpfh):
    with open(fpfh, "r") as f:
        c = f.read()
    if "_USE_MATH_DEFINES" not in c:
        with open(fpfh, "w") as f:
            f.write("#define _USE_MATH_DEFINES\n" + c)
        print("PATCHED fpfh_estimation.cpp")

# Patch 4: point_cloud_cpu.cpp
pcc = os.path.join(src, "src/gtsam_points/types/point_cloud_cpu.cpp")
if os.path.exists(pcc):
    with open(pcc, "r") as f:
        c = f.read()
    old1 = "if (!std::regex_search(itr->path().string(), matched, aux_name_regex))"
    if old1 in c:
        new1 = "std::string _aux_filename = itr->path().string();\n    if (!std::regex_search(_aux_filename, matched, aux_name_regex))"
        c = c.replace(old1, new1)
        with open(pcc, "w") as f:
            f.write(c)
        print("PATCHED point_cloud_cpu.cpp (path().string)")
    else:
        # Debug: show all regex_search lines
        lines = c.split("\n")
        for i, l in enumerate(lines):
            if "regex_search" in l:
                print(f"  DEBUG Line {i+1}: {l.rstrip()[:120]}")
        print("  point_cloud_cpu.cpp: no pattern matched, skipping")

print("Done patching")
