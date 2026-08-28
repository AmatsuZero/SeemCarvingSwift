package io.github.seamcarving;

import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.File;
import java.io.InputStream;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.Set;
import java.util.jar.JarEntry;
import java.util.jar.JarInputStream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;
import org.junit.Test;

public final class ReleaseAarContentsTest {
    @Test
    public void releaseAarPackagesTheBridgeAndRequiredRuntimesForEveryAbi() throws Exception {
        File releaseAar = new File(System.getProperty("releaseAar"));
        assertTrue("Release AAR was not created: " + releaseAar, releaseAar.isFile());

        try (ZipFile aar = new ZipFile(releaseAar)) {
            Set<String> entries = new HashSet<>();
            Enumeration<? extends ZipEntry> zipEntries = aar.entries();
            while (zipEntries.hasMoreElements()) {
                entries.add(zipEntries.nextElement().getName());
            }

            for (String abi : new String[] {"arm64-v8a", "armeabi-v7a", "x86_64"}) {
                for (String library : new String[] {
                    "libSeamCarvingAndroidBridge.so",
                    "libSwiftJava.so",
                    "libc++_shared.so",
                    "libswiftCore.so",
                }) {
                    assertTrue(
                        "Missing jni/" + abi + "/" + library + " from " + releaseAar,
                        entries.contains("jni/" + abi + "/" + library)
                    );
                }
            }
        }
    }

    @Test
    public void releaseAarKeepsGeneratedBindingsOutOfThePublicPackage() throws Exception {
        File releaseAar = new File(System.getProperty("releaseAar"));
        assertTrue("Release AAR was not created: " + releaseAar, releaseAar.isFile());

        Set<String> classes = new HashSet<>();
        try (ZipFile aar = new ZipFile(releaseAar)) {
            ZipEntry classesJar = aar.getEntry("classes.jar");
            assertTrue("Missing classes.jar from " + releaseAar, classesJar != null);
            try (InputStream input = aar.getInputStream(classesJar);
                 JarInputStream jar = new JarInputStream(input)) {
                JarEntry entry;
                while ((entry = jar.getNextJarEntry()) != null) {
                    classes.add(entry.getName());
                }
            }
        }

        for (String publicType : new String[] {
            "Mask", "ResizeRequest", "RgbaImage", "SeamCarver", "SeamCarvingException"
        }) {
            assertTrue(
                "Missing public API type " + publicType,
                classes.contains("io/github/seamcarving/" + publicType + ".class")
            );
        }
        assertTrue(
            "Generated JNI binding is not isolated in the internal package",
            classes.contains("io/github/seamcarving/internal/AndroidResizeBridge.class")
        );
        assertFalse(
            "Generated JNI binding leaked into the public package",
            classes.contains("io/github/seamcarving/AndroidResizeBridge.class")
        );
        assertFalse(
            "Legacy public package remains in the AAR",
            classes.stream().anyMatch(name -> name.startsWith("com/seamcarving/android/core/"))
        );
    }
}
