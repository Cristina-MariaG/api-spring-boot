package org.store.security;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

@Configuration
public class FilterConfig {

    @Value("${api.key}")
    private String apiKey;

    @Bean
    public FilterRegistrationBean<ApiKeyRequestFilter> apiKeyFilter(){
        FilterRegistrationBean<ApiKeyRequestFilter> registrationBean = new FilterRegistrationBean<>();
        registrationBean.setFilter(new ApiKeyRequestFilter(apiKey));
        registrationBean.addUrlPatterns(
            "/api/*",
            "/swagger-ui/*",
            "/swagger-ui.html",
            "/v3/api-docs/*"
        );
        return registrationBean;
    }
}
