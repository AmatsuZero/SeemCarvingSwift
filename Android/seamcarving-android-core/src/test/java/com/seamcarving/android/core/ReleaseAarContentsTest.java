package com.seamcarving.android.core;

import static org.junit.Assert.assertTrue;

import java.io.File;
import java.util.Enumeration;
import java.util.HashSet;
import java.util.Set;
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
}
