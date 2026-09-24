FROM php:8.1-apache
RUN apt-get update && apt-get install -y \
    libzip-dev \
    libicu-dev \
    && docker-php-ext-install zip intl mysqli \
    && docker-php-ext-enable zip intl mysqli
