FROM php:7.4-apache

RUN apt-get update
RUN docker-php-ext-install mysqli && docker-php-ext-enable mysqli

COPY /app /var/www/html/

EXPOSE 80