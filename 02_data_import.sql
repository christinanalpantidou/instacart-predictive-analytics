COPY aisles FROM 'D:/Diplomatiki/Instacart_data/aisles.csv' DELIMITER ',' CSV HEADER;
COPY departments FROM 'D:/Diplomatiki/Instacart_data/departments.csv' DELIMITER ',' CSV HEADER;
COPY orders FROM 'D:/Diplomatiki/Instacart_data/orders.csv' DELIMITER ',' CSV HEADER;
COPY products FROM 'D:/Diplomatiki/Instacart_data/products.csv' DELIMITER ',' CSV HEADER;
COPY order_products_prior FROM 'D:/Diplomatiki/Instacart_data/order_products__prior.csv' DELIMITER ',' CSV HEADER;
COPY order_products_train FROM 'D:/Diplomatiki/Instacart_data/order_products__train.csv' DELIMITER ',' CSV HEADER;

