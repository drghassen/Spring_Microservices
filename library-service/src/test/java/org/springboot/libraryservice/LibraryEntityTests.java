package org.springboot.libraryservice;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

import static org.junit.jupiter.api.Assertions.assertNotNull;

@SpringBootTest
class LibraryEntityTests {

    @Test
    void contextLoads() {
        assertNotNull(LibraryEntityTests.class);
    }
}
