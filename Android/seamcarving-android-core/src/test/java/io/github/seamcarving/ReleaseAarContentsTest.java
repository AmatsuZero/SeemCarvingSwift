package io.github.seamcarving;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import java.io.DataInputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.charset.StandardCharsets;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.Set;
import java.util.jar.JarFile;
import java.util.jar.JarEntry;
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
    public void releaseAarExposesOnlyTheStableFacadeAndKeepsTheBridgePackagePrivate() throws Exception {
        File releaseAar = new File(System.getProperty("releaseAar"));
        File bridgeRuntimeJar = new File(System.getProperty("bridgeRuntimeJar", ""));
        assertTrue("Release AAR was not created: " + releaseAar, releaseAar.isFile());
        assertTrue("Generated bridge runtime JAR was not created: " + bridgeRuntimeJar, bridgeRuntimeJar.isFile());

        Path classesJarPath = Files.createTempFile("seamcarving-release-classes", ".jar");
        try (ZipFile aar = new ZipFile(releaseAar)) {
            ZipEntry classesJar = aar.getEntry("classes.jar");
            assertTrue("Missing classes.jar from " + releaseAar, classesJar != null);
            try (InputStream input = aar.getInputStream(classesJar);
                 FileOutputStream output = new FileOutputStream(classesJarPath.toFile())) {
                input.transferTo(output);
            }
        }

        try (JarFile classesJar = new JarFile(classesJarPath.toFile())) {
            Set<String> classes = new HashSet<>();
            Enumeration<JarEntry> entries = classesJar.entries();
            while (entries.hasMoreElements()) {
                classes.add(entries.nextElement().getName());
            }

            for (String publicType : new String[] {
                "Mask", "ResizeRequest", "RgbaImage", "SeamCarver", "SeamCarvingException"
            }) {
                assertTrue(
                    "Missing public API type " + publicType,
                    classes.contains("io/github/seamcarving/" + publicType + ".class")
                );
            }
            assertFalse(
                "Legacy source package remains in the AAR",
                classes.stream().anyMatch(name -> name.startsWith("com/seamcarving/android/core/"))
            );
            assertFalse(
                "Generated bridge implementation must be supplied by its runtime dependency, not the core AAR",
                classes.stream().anyMatch(name -> name.startsWith("io/github/seamcarving/AndroidResize"))
            );
            assertFalse(
                "SwiftKitCore classes must be supplied by a Gradle runtime dependency, not duplicated in the AAR",
                classes.stream().anyMatch(name -> name.startsWith("org/swift/swiftkit/core/"))
            );
        }

        try (JarFile bridgeJar = new JarFile(bridgeRuntimeJar)) {
            assertFalse(
                "Generated bridge JAR retained the obsolete internal package",
                classEntries(bridgeRuntimeJar).stream()
                    .anyMatch(name -> name.startsWith("io/github/seamcarving/internal/"))
            );
            for (String bridgeType : new String[] {
                "AndroidResizeBridge", "AndroidResizeResult", "BridgeProbe", "SeamCarvingAndroidBridge"
            }) {
                String classEntry = "io/github/seamcarving/" + bridgeType + ".class";
                assertTrue("Missing generated bridge type " + bridgeType, bridgeJar.getEntry(classEntry) != null);
                try (DataInputStream input = new DataInputStream(bridgeJar.getInputStream(bridgeJar.getEntry(classEntry)))) {
                    assertFalse(
                        "Generated bridge type is JVM-public: " + bridgeType,
                        (readClassAccessFlags(input) & 0x0001) != 0
                    );
                }
            }
        }

        assertConsumerCompilation(new Path[] {classesJarPath}, "StableConsumer", """
            import io.github.seamcarving.RgbaImage;
            final class StableConsumer { RgbaImage image; }
            """, true);
        assertConsumerCompilation(new Path[] {
            classesJarPath,
            bridgeRuntimeJar.toPath(),
            Path.of(System.getProperty("swiftKitRuntimeJar"))
        }, "LeakyConsumer", """
            import io.github.seamcarving.AndroidResizeBridge;
            final class LeakyConsumer { AndroidResizeBridge bridge; }
            """, false);
    }

    @Test
    public void swiftKitRuntimeUsesAnOwnedCoordinateWithoutDuplicateClasses() throws Exception {
        File releaseAar = new File(System.getProperty("releaseAar"));
        File runtimeJar = new File(System.getProperty("swiftKitRuntimeJar", ""));
        File bridgeRuntimeJar = new File(System.getProperty("bridgeRuntimeJar", ""));
        assertTrue("SwiftKitCore runtime dependency JAR was not created: " + runtimeJar, runtimeJar.isFile());
        assertEquals(
            "The vendored SwiftKit runtime must use a SeamCarving-owned, versioned coordinate",
            "io.github.seamcarving:seamcarving-swiftkit-runtime:0.1.0-SNAPSHOT",
            System.getProperty("swiftKitRuntimeCoordinate")
        );

        Set<String> coreClasses = new HashSet<>();
        try (ZipFile aar = new ZipFile(releaseAar)) {
            ZipEntry classesJar = aar.getEntry("classes.jar");
            try (InputStream input = aar.getInputStream(classesJar);
                 java.util.jar.JarInputStream jar = new java.util.jar.JarInputStream(input)) {
                JarEntry entry;
                while ((entry = jar.getNextJarEntry()) != null) {
                    if (entry.getName().endsWith(".class")) coreClasses.add(entry.getName());
                }
            }
        }

        Set<String> runtimeClasses = new HashSet<>();
        try (JarFile jar = new JarFile(runtimeJar)) {
            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                if (entry.getName().endsWith(".class")) runtimeClasses.add(entry.getName());
            }
        }
        assertTrue(
            "The separate runtime JAR must provide real Swift object destruction",
            runtimeClasses.contains("org/swift/swiftkit/core/SwiftObjects.class")
        );
        Set<String> bridgeClasses = classEntries(bridgeRuntimeJar);
        Set<String> duplicates = new HashSet<>(coreClasses);
        duplicates.retainAll(runtimeClasses);
        assertTrue("Core AAR duplicates SwiftKit runtime classes: " + duplicates, duplicates.isEmpty());
        duplicates = new HashSet<>(bridgeClasses);
        duplicates.retainAll(runtimeClasses);
        assertTrue("Bridge runtime duplicates SwiftKit runtime classes: " + duplicates, duplicates.isEmpty());
    }

    @Test
    public void publishedCorePomDeliversBothPrivateRuntimeModulesTransitively() throws Exception {
        File corePom = latestPom(new File(System.getProperty("corePomDirectory", "")));
        File bridgePom = latestPom(new File(System.getProperty("bridgePomDirectory", "")));
        File swiftKitPom = latestPom(new File(System.getProperty("swiftKitPomDirectory", "")));

        String core = new String(Files.readAllBytes(corePom.toPath()), StandardCharsets.UTF_8);
        String bridge = new String(Files.readAllBytes(bridgePom.toPath()), StandardCharsets.UTF_8);
        assertTrue(core.contains("<artifactId>seamcarving-android-bridge</artifactId>"));
        assertTrue(core.contains("<artifactId>seamcarving-swiftkit-runtime</artifactId>"));
        assertTrue(bridge.contains("<artifactId>seamcarving-swiftkit-runtime</artifactId>"));
        assertFalse(core.contains("<groupId>org.swift.swiftkit</groupId>"));
        assertFalse(bridge.contains("<groupId>org.swift.swiftkit</groupId>"));
        assertTrue("Private bridge must be a runtime-only consumer dependency", dependencyHasRuntimeScope(core, "seamcarving-android-bridge"));
        assertTrue("SwiftKit must be a runtime-only consumer dependency", dependencyHasRuntimeScope(core, "seamcarving-swiftkit-runtime"));
    }

    private static File latestPom(File directory) {
        File[] poms = directory.listFiles((ignored, name) -> name.endsWith(".pom"));
        assertTrue("Expected a published Maven POM in " + directory, poms != null && poms.length > 0);
        File latest = poms[0];
        for (File pom : poms) {
            if (pom.lastModified() > latest.lastModified()) latest = pom;
        }
        return latest;
    }

    private static boolean dependencyHasRuntimeScope(String pom, String artifactId) {
        int artifact = pom.indexOf("<artifactId>" + artifactId + "</artifactId>");
        if (artifact < 0) return false;
        int dependencyEnd = pom.indexOf("</dependency>", artifact);
        if (dependencyEnd < 0) return false;
        return pom.substring(artifact, dependencyEnd).contains("<scope>runtime</scope>");
    }

    private static Set<String> classEntries(File jarFile) throws Exception {
        Set<String> classes = new HashSet<>();
        try (JarFile jar = new JarFile(jarFile)) {
            Enumeration<JarEntry> entries = jar.entries();
            while (entries.hasMoreElements()) {
                JarEntry entry = entries.nextElement();
                if (entry.getName().endsWith(".class")) classes.add(entry.getName());
            }
        }
        return classes;
    }

    private static void assertConsumerCompilation(
        Path[] classpathEntries,
        String className,
        String source,
        boolean expectedSuccess
    ) throws Exception {
        Path output = Files.createTempDirectory("seamcarving-consumer-compile");
        Path sourceFile = output.resolve(className + ".java");
        Files.write(sourceFile, source.getBytes());
        Path javac = Path.of(System.getProperty("java.home"), "bin", "javac");
        assertTrue("Release AAR API test requires a full JDK: " + javac, Files.isExecutable(javac));
        StringBuilder classpath = new StringBuilder();
        for (Path entry : classpathEntries) {
            if (classpath.length() > 0) classpath.append(File.pathSeparator);
            classpath.append(entry);
        }
        Process process = new ProcessBuilder(
            javac.toString(),
            "-classpath", classpath.toString(),
            "-d", output.toString(),
            sourceFile.toString()
        ).redirectErrorStream(true).start();
        String diagnostics = new String(process.getInputStream().readAllBytes());
        boolean success = process.waitFor() == 0;
        if (expectedSuccess) {
            assertTrue("Stable facade did not compile: " + diagnostics, success);
        } else {
            assertFalse("Generated bridge unexpectedly compiled as consumer API", success);
        }
    }

    private static int readClassAccessFlags(DataInputStream input) throws Exception {
        if (input.readInt() != 0xCAFEBABE) {
            throw new IllegalArgumentException("Not a JVM class file");
        }
        input.readUnsignedShort();
        input.readUnsignedShort();
        int constantPoolCount = input.readUnsignedShort();
        for (int index = 1; index < constantPoolCount; index++) {
            int tag = input.readUnsignedByte();
            switch (tag) {
                case 1 -> input.skipBytes(input.readUnsignedShort());
                case 3, 4, 9, 10, 11, 12, 17, 18 -> input.skipBytes(4);
                case 5, 6 -> { input.skipBytes(8); index++; }
                case 7, 8, 16, 19, 20 -> input.skipBytes(2);
                case 15 -> input.skipBytes(3);
                default -> throw new IllegalArgumentException("Unknown constant pool tag: " + tag);
            }
        }
        return input.readUnsignedShort();
    }
}
