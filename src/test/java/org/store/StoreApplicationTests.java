package org.store;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import javax.sql.DataSource;

@SpringBootTest
class StoreApplicationTests {

    @MockBean
    DataSource dataSource;

    @Test
    void contextLoads() {
    }

}
