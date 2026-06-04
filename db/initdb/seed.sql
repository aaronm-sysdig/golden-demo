CREATE TABLE customers (
    id      SERIAL PRIMARY KEY,
    name    TEXT NOT NULL,
    email   TEXT NOT NULL,
    card    TEXT NOT NULL
);

INSERT INTO customers (name, email, card) VALUES
    ('Alice Hopper',   'alice.hopper@example.com',   '4111-1111-1111-1111'),
    ('Bilal Rashid',   'bilal.rashid@example.com',   '4222-2222-2222-2222'),
    ('Carmen Diaz',    'carmen.diaz@example.com',    '4333-3333-3333-3333'),
    ('Deepak Nair',    'deepak.nair@example.com',    '4444-4444-4444-4444'),
    ('Evelyn Stone',   'evelyn.stone@example.com',   '4555-5555-5555-5555'),
    ('Farah Osman',    'farah.osman@example.com',    '4666-6666-6666-6666'),
    ('Gus Lindqvist',  'gus.lindqvist@example.com',  '4777-7777-7777-7777'),
    ('Hana Kim',       'hana.kim@example.com',       '4888-8888-8888-8888');
