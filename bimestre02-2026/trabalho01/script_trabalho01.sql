/* =====================================================================
   TRABALHO PRÁTICO 01 - GESTÃO DE BANCO DE DADOS (PostgreSQL)
   Projeto: Terceira Camisa - loja de camisas esportivas importadas
   Aluno: (preencher)          RA: (preencher)

   1. JUSTIFICATIVA DA ESCOLHA DO TEMA
   ---------------------------------------------------------------------
   Escolhi esse tema porque o mercado de camisas oficiais importadas tem
   uma dinâmica bem diferente de uma loja comum. Quase nada fica em
   estoque: o cliente escolhe o modelo, a loja pede ao fornecedor no
   exterior e a camisa leva semanas para chegar. Isso gera situações que
   dão uma modelagem interessante, como pedido com várias etapas,
   pagamento dividido em sinal e saldo e camisas personalizadas com nome
   e número.

   2. CONTEXTUALIZAÇÃO DO NEGÓCIO
   ---------------------------------------------------------------------
   A Terceira Camisa é uma loja fictícia que vende camisas de clubes e
   seleções estrangeiras, principalmente sob encomenda. O fluxo é este:
     a) o cliente faz o pedido e escolhe produto, tamanho e, se quiser,
        nome e número nas costas;
     b) paga um sinal (ou o valor total) para a loja confirmar a compra;
     c) a loja encomenda a camisa no fornecedor do exterior;
     d) o pedido passa por "encomendado", "em trânsito" e "chegou";
     e) o cliente paga o saldo e o pedido é entregue.
   O banco foi pensado para responder perguntas do dia a dia: quais
   pedidos estão atrasados, quanto cada cliente ainda deve, quais camisas
   mais saem e qual fornecedor movimenta mais pedidos.

   3. ESTRUTURA DO ARQUIVO
   ---------------------------------------------------------------------
   Parte 1 - Criação das tabelas (com PK, NOT NULL, UNIQUE, DEFAULT, CHECK)
   Parte 2 - Chaves estrangeiras (relacionamentos entre as tabelas)
   Parte 3 - Inserção dos dados (entre 5 e 10 registros por tabela)
   Parte 4 - Consultas SQL
   ===================================================================== */


/* Limpeza inicial: serve só para poder rodar o script mais de uma vez.
   A ordem é do filho para o pai, porque as tabelas filhas dependem
   das tabelas pai por causa das chaves estrangeiras. */
DROP TABLE IF EXISTS pagamentos;
DROP TABLE IF EXISTS itens_pedido;
DROP TABLE IF EXISTS pedidos;
DROP TABLE IF EXISTS produtos;
DROP TABLE IF EXISTS clientes;
DROP TABLE IF EXISTS fornecedores;


/* =====================================================================
   PARTE 1 - CRIAÇÃO DAS TABELAS
   As tabelas são criadas das independentes para as dependentes:
   fornecedores e clientes primeiro, depois produtos, pedidos,
   itens_pedido e pagamentos.
   ===================================================================== */

-- ---------------------------------------------------------------------
-- Tabela FORNECEDORES
-- Objetivo: guardar as lojas e distribuidores no exterior de onde a
-- Terceira Camisa compra as camisas. O prazo médio de entrega ajuda a
-- calcular a previsão dos pedidos e a comparar fornecedores. O campo
-- "ativo" permite desativar um fornecedor sem apagar o histórico.
-- ---------------------------------------------------------------------
CREATE TABLE fornecedores (
    id_fornecedor    SERIAL        PRIMARY KEY,
    nome             VARCHAR(100)  NOT NULL UNIQUE,
    pais             VARCHAR(50)   NOT NULL,
    email_contato    VARCHAR(120)  NOT NULL UNIQUE,
    prazo_medio_dias INTEGER       NOT NULL,
    ativo            BOOLEAN       NOT NULL DEFAULT TRUE,
    -- o prazo de entrega precisa ser um número positivo de dias
    CONSTRAINT ck_fornecedores_prazo CHECK (prazo_medio_dias > 0)
);

-- ---------------------------------------------------------------------
-- Tabela CLIENTES
-- Objetivo: cadastro de quem compra na loja. O CPF e o e-mail são únicos
-- para não cadastrar a mesma pessoa duas vezes. A data de cadastro
-- recebe a data do dia automaticamente quando não é informada. O
-- telefone é o único campo opcional.
-- ---------------------------------------------------------------------
CREATE TABLE clientes (
    id_cliente    SERIAL        PRIMARY KEY,
    nome          VARCHAR(100)  NOT NULL,
    cpf           CHAR(11)      NOT NULL UNIQUE,
    email         VARCHAR(120)  NOT NULL UNIQUE,
    telefone      VARCHAR(15),
    cidade        VARCHAR(60)   NOT NULL,
    uf            CHAR(2)       NOT NULL,
    data_cadastro DATE          NOT NULL DEFAULT CURRENT_DATE,
    -- o CPF deve ter exatamente 11 dígitos numéricos
    CONSTRAINT ck_clientes_cpf CHECK (cpf ~ '^[0-9]{11}$'),
    -- a UF deve ter duas letras maiúsculas (MG, SP...)
    CONSTRAINT ck_clientes_uf CHECK (uf ~ '^[A-Z]{2}$'),
    -- validação simples: o e-mail precisa ter uma arroba
    CONSTRAINT ck_clientes_email CHECK (email LIKE '%@%')
);

-- ---------------------------------------------------------------------
-- Tabela PRODUTOS
-- Objetivo: catálogo de camisas que a loja consegue encomendar. Cada
-- produto é uma camisa específica (clube ou seleção, temporada, modelo
-- e versão) e está ligado ao fornecedor que a vende. Guarda o preço de
-- venda e o custo de importação para dar para ver a margem de cada uma.
-- ---------------------------------------------------------------------
CREATE TABLE produtos (
    id_produto       SERIAL        PRIMARY KEY,
    id_fornecedor    INTEGER       NOT NULL,
    clube_selecao    VARCHAR(80)   NOT NULL,
    temporada        VARCHAR(7)    NOT NULL,
    modelo           VARCHAR(10)   NOT NULL,
    versao           VARCHAR(10)   NOT NULL DEFAULT 'torcedor',
    preco_venda      NUMERIC(10,2) NOT NULL,
    custo_importacao NUMERIC(10,2) NOT NULL,
    ativo            BOOLEAN       NOT NULL DEFAULT TRUE,
    -- a mesma camisa não pode aparecer duas vezes no catálogo
    CONSTRAINT uq_produtos_camisa UNIQUE (clube_selecao, temporada, modelo, versao),
    -- temporada no formato 2025/26 (europeia) ou 2026 (ano único)
    CONSTRAINT ck_produtos_temporada CHECK (temporada ~ '^[0-9]{4}(/[0-9]{2})?$'),
    CONSTRAINT ck_produtos_modelo CHECK (modelo IN ('home', 'away', 'third')),
    CONSTRAINT ck_produtos_versao CHECK (versao IN ('torcedor', 'jogador', 'retro')),
    CONSTRAINT ck_produtos_custo  CHECK (custo_importacao > 0),
    -- a loja não pode vender abaixo do custo de importação
    CONSTRAINT ck_produtos_preco  CHECK (preco_venda > custo_importacao)
);

-- ---------------------------------------------------------------------
-- Tabela PEDIDOS
-- Objetivo: é o cabeçalho de cada encomenda. Registra quem pediu, quando
-- pediu, em que etapa o pedido está (status) e a data prevista de
-- entrega. Os produtos de cada pedido ficam na tabela itens_pedido.
-- A previsão pode ficar vazia em pedidos cancelados.
-- ---------------------------------------------------------------------
CREATE TABLE pedidos (
    id_pedido        SERIAL       PRIMARY KEY,
    id_cliente       INTEGER      NOT NULL,
    data_pedido      DATE         NOT NULL DEFAULT CURRENT_DATE,
    status           VARCHAR(25)  NOT NULL DEFAULT 'aguardando_pagamento',
    previsao_entrega DATE,
    CONSTRAINT ck_pedidos_status CHECK (status IN (
        'aguardando_pagamento', 'encomendado', 'em_transito',
        'chegou', 'entregue', 'cancelado')),
    -- a previsão de entrega não pode ser anterior à data do pedido
    CONSTRAINT ck_pedidos_previsao CHECK (
        previsao_entrega IS NULL OR previsao_entrega >= data_pedido)
);

-- ---------------------------------------------------------------------
-- Tabela ITENS_PEDIDO
-- Objetivo: lista as camisas de cada pedido. Um pedido pode ter várias
-- camisas e uma mesma camisa pode aparecer em vários pedidos, então
-- essa tabela resolve o relacionamento N:N entre pedidos e produtos.
-- O preço unitário é copiado para cá no momento da venda, assim se o
-- catálogo mudar de preço depois, os pedidos antigos continuam certos.
-- Nome e número servem para camisas personalizadas.
-- ---------------------------------------------------------------------
CREATE TABLE itens_pedido (
    id_item              SERIAL        PRIMARY KEY,
    id_pedido            INTEGER       NOT NULL,
    id_produto           INTEGER       NOT NULL,
    tamanho              VARCHAR(3)    NOT NULL,
    quantidade           INTEGER       NOT NULL DEFAULT 1,
    preco_unitario       NUMERIC(10,2) NOT NULL,
    nome_personalizado   VARCHAR(20),
    numero_personalizado SMALLINT,
    -- evita repetir a mesma camisa e tamanho dentro do mesmo pedido
    CONSTRAINT uq_itens_pedido_produto UNIQUE (id_pedido, id_produto, tamanho),
    CONSTRAINT ck_itens_tamanho    CHECK (tamanho IN ('P', 'M', 'G', 'GG', 'XGG')),
    CONSTRAINT ck_itens_quantidade CHECK (quantidade > 0),
    CONSTRAINT ck_itens_preco      CHECK (preco_unitario > 0),
    CONSTRAINT ck_itens_numero     CHECK (numero_personalizado BETWEEN 0 AND 99),
    -- personalização precisa ter nome e número juntos, ou nenhum dos dois
    CONSTRAINT ck_itens_personalizacao CHECK (
        (nome_personalizado IS NULL) = (numero_personalizado IS NULL))
);

-- ---------------------------------------------------------------------
-- Tabela PAGAMENTOS
-- Objetivo: registra cada pagamento feito por um pedido. Como a venda é
-- sob encomenda, um mesmo pedido costuma ter dois pagamentos (sinal e
-- saldo), por isso o pagamento tem tabela própria. A situação mostra se
-- o dinheiro já foi confirmado, está pendente ou foi estornado.
-- A coluna data_registro guarda o dia em que o pagamento foi lançado no
-- sistema: para pix e cartão é o dia do pagamento, e para um boleto
-- pendente é o dia em que ele foi gerado.
-- ---------------------------------------------------------------------
CREATE TABLE pagamentos (
    id_pagamento  SERIAL        PRIMARY KEY,
    id_pedido     INTEGER       NOT NULL,
    tipo          VARCHAR(10)   NOT NULL,
    forma         VARCHAR(10)   NOT NULL,
    valor         NUMERIC(10,2) NOT NULL,
    data_registro DATE          NOT NULL DEFAULT CURRENT_DATE,
    situacao      VARCHAR(12)   NOT NULL DEFAULT 'pendente',
    CONSTRAINT ck_pagamentos_tipo     CHECK (tipo IN ('sinal', 'saldo', 'integral')),
    CONSTRAINT ck_pagamentos_forma    CHECK (forma IN ('pix', 'cartao', 'boleto')),
    CONSTRAINT ck_pagamentos_valor    CHECK (valor > 0),
    CONSTRAINT ck_pagamentos_situacao CHECK (situacao IN ('pendente', 'confirmado', 'estornado'))
);


/* =====================================================================
   PARTE 2 - CHAVES ESTRANGEIRAS (RELACIONAMENTOS)
   Deixei as FKs separadas das tabelas para ficar claro como elas se
   ligam. Usei o comportamento padrão (NO ACTION): o banco não deixa
   apagar um registro que ainda é usado por outra tabela, o que protege
   o histórico de vendas.
   ===================================================================== */

-- Um fornecedor tem vários produtos
ALTER TABLE produtos
    ADD CONSTRAINT fk_produtos_fornecedor
    FOREIGN KEY (id_fornecedor) REFERENCES fornecedores (id_fornecedor);

-- Um cliente faz vários pedidos
ALTER TABLE pedidos
    ADD CONSTRAINT fk_pedidos_cliente
    FOREIGN KEY (id_cliente) REFERENCES clientes (id_cliente);

-- Um pedido tem vários itens
ALTER TABLE itens_pedido
    ADD CONSTRAINT fk_itens_pedido
    FOREIGN KEY (id_pedido) REFERENCES pedidos (id_pedido);

-- Um produto pode estar em vários itens de pedidos diferentes
ALTER TABLE itens_pedido
    ADD CONSTRAINT fk_itens_produto
    FOREIGN KEY (id_produto) REFERENCES produtos (id_produto);

-- Um pedido pode ter vários pagamentos (sinal, saldo)
ALTER TABLE pagamentos
    ADD CONSTRAINT fk_pagamentos_pedido
    FOREIGN KEY (id_pedido) REFERENCES pedidos (id_pedido);


/* =====================================================================
   PARTE 3 - INSERÇÃO DOS DADOS
   Os ids são gerados pelo SERIAL na ordem dos INSERTs (1, 2, 3...).
   Por isso as chaves estrangeiras usam esses números. Os dados são
   todos fictícios, inclusive CPFs, e-mails e telefones.
   Cada tabela tem entre 5 e 10 registros.
   Cuidei da ordem das datas: o cliente se cadastra antes de pedir, o
   pagamento vem depois do pedido, o saldo vem depois do sinal e a
   previsão de entrega considera o prazo do fornecedor mais o tempo de
   frete e entrega no Brasil.
   ===================================================================== */

-- ---------------------------------------------------------------------
-- Fornecedores (6 registros)
-- O fornecedor 6 está inativo: o catálogo retrô dele foi suspenso.
-- ---------------------------------------------------------------------
INSERT INTO fornecedores (nome, pais, email_contato, prazo_medio_dias, ativo) VALUES
('Premier Kits Ltd',        'Inglaterra', 'vendas@premierkits.example.com',       21, TRUE),
('Calcio Store Milano',     'Itália',     'ordini@calciostore.example.com',       18, TRUE),
('Camisetas del Sur',       'Argentina',  'pedidos@camisetasdelsur.example.com',  12, TRUE),
('Bundesliga Trikots GmbH', 'Alemanha',   'verkauf@bltrikots.example.com',        25, TRUE),
('Lusa Camisolas',          'Portugal',   'encomendas@lusacamisolas.example.com', 15, TRUE),
('Fútbol Clásico SL',       'Espanha',    'contacto@futbolclasico.example.com',   30, FALSE);

-- ---------------------------------------------------------------------
-- Clientes (8 registros)
-- ---------------------------------------------------------------------
INSERT INTO clientes (nome, cpf, email, telefone, cidade, uf, data_cadastro) VALUES
('Rafael Moreira Costa',   '11122233344', 'rafael.costa@exemplo.com.br',   '31991234567', 'Belo Horizonte', 'MG', '2026-05-28'),
('Camila Duarte Lima',     '22233344455', 'camila.lima@exemplo.com.br',    '31988776655', 'Contagem',       'MG', '2026-06-20'),
('Thiago Alves Pereira',   '33344455566', 'thiago.pereira@exemplo.com.br', '11977665544', 'São Paulo',      'SP', '2026-08-10'),
('Juliana Rocha Santos',   '44455566677', 'juliana.santos@exemplo.com.br', '21966554433', 'Rio de Janeiro', 'RJ', '2026-08-30'),
('Bruno Henrique Faria',   '55566677788', 'bruno.faria@exemplo.com.br',    '31955443322', 'Betim',          'MG', '2026-09-25'),
('Larissa Menezes Cunha',  '66677788899', 'larissa.cunha@exemplo.com.br',  '41944332211', 'Curitiba',       'PR', '2026-10-10'),
('Gustavo Ribeiro Prado',  '77788899900', 'gustavo.prado@exemplo.com.br',  '34933221100', 'Uberlândia',     'MG', '2026-10-27'),
('Patrícia Nogueira Dias', '88899900011', 'patricia.dias@exemplo.com.br',  '71922110099', 'Salvador',       'BA', '2026-10-18');

-- ---------------------------------------------------------------------
-- Produtos (10 registros)
-- A coluna id_fornecedor aponta para a tabela fornecedores.
-- O produto 10 é uma camisa retrô do fornecedor inativo, então também
-- está marcado como inativo.
-- ---------------------------------------------------------------------
INSERT INTO produtos (id_fornecedor, clube_selecao, temporada, modelo, versao, preco_venda, custo_importacao, ativo) VALUES
(1, 'Manchester City',   '2025/26', 'home',  'torcedor', 349.90, 240.00, TRUE),
(1, 'Arsenal',           '2025/26', 'away',  'torcedor', 339.90, 235.00, TRUE),
(1, 'Liverpool',         '2025/26', 'third', 'jogador',  499.90, 350.00, TRUE),
(2, 'Inter de Milão',    '2025/26', 'home',  'torcedor', 359.90, 245.00, TRUE),
(2, 'Milan',             '2025/26', 'away',  'torcedor', 349.90, 240.00, TRUE),
(3, 'Boca Juniors',      '2025/26', 'home',  'torcedor', 279.90, 170.00, TRUE),
(4, 'Bayern de Munique', '2025/26', 'home',  'jogador',  529.90, 380.00, TRUE),
(5, 'Benfica',           '2025/26', 'home',  'torcedor', 319.90, 215.00, TRUE),
(3, 'Seleção Argentina', '2026',    'home',  'torcedor', 299.90, 185.00, TRUE),
(6, 'Barcelona',         '1998/99', 'home',  'retro',    429.90, 310.00, FALSE);

-- ---------------------------------------------------------------------
-- Pedidos (9 registros)
-- Cobrem as etapas do fluxo: entregue, chegou, em trânsito, encomendado,
-- aguardando pagamento e cancelado. O pedido 5 está atrasado (a previsão
-- já passou e a camisa ainda não chegou). O pedido 8 foi cancelado antes
-- de qualquer pagamento, por isso não tem previsão de entrega.
-- ---------------------------------------------------------------------
INSERT INTO pedidos (id_cliente, data_pedido, status, previsao_entrega) VALUES
(1, '2026-06-10', 'entregue',             '2026-07-15'),
(2, '2026-07-02', 'entregue',             '2026-08-05'),
(3, '2026-08-14', 'entregue',             '2026-09-09'),
(4, '2026-09-05', 'chegou',               '2026-10-14'),
(1, '2026-09-20', 'em_transito',          '2026-10-25'),
(5, '2026-10-12', 'em_transito',          '2026-11-09'),
(6, '2026-10-15', 'encomendado',          '2026-11-17'),
(8, '2026-10-20', 'cancelado',            NULL),
(7, '2026-10-28', 'aguardando_pagamento', '2026-12-02');

-- ---------------------------------------------------------------------
-- Itens dos pedidos (10 registros)
-- No item 1 o preço unitário (339,90) é diferente do preço atual do
-- catálogo (349,90): o produto foi reajustado depois da venda e o
-- pedido antigo continua com o valor que o cliente pagou.
-- O pedido 2 tem duas camisas diferentes e o pedido 7 tem uma camisa
-- com quantidade 2.
-- ---------------------------------------------------------------------
INSERT INTO itens_pedido (id_pedido, id_produto, tamanho, quantidade, preco_unitario, nome_personalizado, numero_personalizado) VALUES
(1, 1,  'G',  1, 339.90, 'HAALAND',  9),
(2, 4,  'M',  1, 359.90, NULL,       NULL),
(2, 5,  'M',  1, 349.90, NULL,       NULL),
(3, 6,  'GG', 1, 279.90, 'RIQUELME', 10),
(4, 7,  'G',  1, 529.90, 'KANE',     9),
(5, 3,  'M',  1, 499.90, 'SALAH',    11),
(6, 9,  'G',  1, 299.90, 'MESSI',    10),
(7, 8,  'P',  2, 319.90, NULL,       NULL),
(8, 10, 'G',  1, 429.90, NULL,       NULL),
(9, 1,  'M',  1, 349.90, NULL,       NULL);

-- ---------------------------------------------------------------------
-- Pagamentos (10 registros)
-- O total de cada pedido é a soma dos itens. Os pedidos pagos em duas
-- vezes têm "sinal" e "saldo" que somam o valor do pedido (pedidos 2 e
-- 4). Os pedidos 1, 3 e 7 foram pagos integralmente. O pedido 4 tem o
-- saldo em boleto ainda pendente. Os pedidos 5 e 6 têm só o sinal pago.
-- O pedido 9 tem só um boleto de sinal pendente e o pedido 8, cancelado,
-- não tem pagamentos.
-- ---------------------------------------------------------------------
INSERT INTO pagamentos (id_pedido, tipo, forma, valor, data_registro, situacao) VALUES
(1, 'integral', 'pix',    339.90, '2026-06-10', 'confirmado'),
(2, 'sinal',    'pix',    354.90, '2026-07-02', 'confirmado'),
(2, 'saldo',    'pix',    354.90, '2026-08-06', 'confirmado'),
(3, 'integral', 'cartao', 279.90, '2026-08-14', 'confirmado'),
(4, 'sinal',    'pix',    264.95, '2026-09-05', 'confirmado'),
(4, 'saldo',    'boleto', 264.95, '2026-10-15', 'pendente'),
(5, 'sinal',    'cartao', 249.95, '2026-09-20', 'confirmado'),
(6, 'sinal',    'pix',    150.00, '2026-10-12', 'confirmado'),
(7, 'integral', 'pix',    639.80, '2026-10-15', 'confirmado'),
(9, 'sinal',    'boleto', 175.00, '2026-10-28', 'pendente');


/* =====================================================================
   PARTE 4 - CONSULTAS SQL
   ===================================================================== */

-- ---------------------------------------------------------------------
-- Consulta 1 - Pedidos em andamento
-- Mostra os pedidos que ainda não foram entregues nem cancelados, com o
-- nome do cliente. Usa JOIN entre pedidos e clientes e filtro WHERE.
-- ---------------------------------------------------------------------
SELECT p.id_pedido,
       c.nome AS cliente,
       p.data_pedido,
       p.status,
       p.previsao_entrega
FROM pedidos p
JOIN clientes c ON c.id_cliente = p.id_cliente
WHERE p.status NOT IN ('entregue', 'cancelado')
ORDER BY p.previsao_entrega;

-- ---------------------------------------------------------------------
-- Consulta 2 - Catálogo ativo com fornecedor e margem de lucro
-- Junta produtos com fornecedores e calcula quanto a loja ganha por
-- camisa (preço de venda menos custo de importação). WHERE filtra só os
-- produtos ativos.
-- ---------------------------------------------------------------------
SELECT pr.clube_selecao,
       pr.temporada,
       pr.modelo,
       pr.versao,
       f.nome AS fornecedor,
       pr.preco_venda,
       pr.preco_venda - pr.custo_importacao AS margem
FROM produtos pr
JOIN fornecedores f ON f.id_fornecedor = pr.id_fornecedor
WHERE pr.ativo = TRUE
ORDER BY margem DESC;

-- ---------------------------------------------------------------------
-- Consulta 3 - Valor total de cada pedido
-- Para cada pedido, conta quantas linhas de itens ele tem (COUNT), soma
-- quantas camisas foram pedidas no total (SUM da quantidade) e soma o
-- valor (quantidade x preço unitário). Pedidos cancelados ficam de fora
-- pelo WHERE. As duas primeiras colunas são diferentes: o pedido 7, por
-- exemplo, tem 1 linha de item mas 2 camisas.
-- ---------------------------------------------------------------------
SELECT p.id_pedido,
       c.nome AS cliente,
       COUNT(i.id_item) AS qtd_itens,
       SUM(i.quantidade) AS qtd_camisas,
       SUM(i.quantidade * i.preco_unitario) AS valor_total
FROM pedidos p
JOIN clientes c     ON c.id_cliente = p.id_cliente
JOIN itens_pedido i ON i.id_pedido  = p.id_pedido
WHERE p.status <> 'cancelado'
GROUP BY p.id_pedido, c.nome
ORDER BY valor_total DESC;

-- ---------------------------------------------------------------------
-- Consulta 4 - Quanto cada cliente já pagou
-- Considera só pagamentos confirmados (WHERE). Conta os pagamentos e
-- soma os valores por cliente. Agrupei pelo id e pelo nome, porque dois
-- clientes diferentes podem ter o mesmo nome e não podem ser somados
-- juntos. Clientes sem nenhum pagamento confirmado não aparecem.
-- ---------------------------------------------------------------------
SELECT c.id_cliente,
       c.nome,
       COUNT(pg.id_pagamento) AS qtd_pagamentos,
       SUM(pg.valor) AS total_pago
FROM clientes c
JOIN pedidos p     ON p.id_cliente = c.id_cliente
JOIN pagamentos pg ON pg.id_pedido = p.id_pedido
WHERE pg.situacao = 'confirmado'
GROUP BY c.id_cliente, c.nome
ORDER BY total_pago DESC;

-- ---------------------------------------------------------------------
-- Consulta 5 - Saldo devedor dos pedidos em aberto
-- Compara o total de cada pedido com o que já foi pago e confirmado.
-- Pagamentos pendentes (como boleto não compensado) não entram na conta.
-- Como itens e pagamentos são duas listas diferentes, somei cada uma
-- numa subconsulta separada antes de juntar. Se eu juntasse as duas
-- tabelas direto, os valores seriam somados em duplicidade.
-- O LEFT JOIN mantém pedidos que ainda não têm pagamento confirmado.
-- Saldo zero significa que o pedido já está quitado, mesmo ainda não
-- tendo sido entregue.
-- ---------------------------------------------------------------------
SELECT p.id_pedido,
       c.nome AS cliente,
       p.status,
       t.total_pedido,
       COALESCE(pg.total_pago, 0) AS total_pago,
       t.total_pedido - COALESCE(pg.total_pago, 0) AS saldo_devedor
FROM pedidos p
JOIN clientes c ON c.id_cliente = p.id_cliente
JOIN (SELECT id_pedido,
             SUM(quantidade * preco_unitario) AS total_pedido
      FROM itens_pedido
      GROUP BY id_pedido) t ON t.id_pedido = p.id_pedido
LEFT JOIN (SELECT id_pedido,
                  SUM(valor) AS total_pago
           FROM pagamentos
           WHERE situacao = 'confirmado'
           GROUP BY id_pedido) pg ON pg.id_pedido = p.id_pedido
WHERE p.status NOT IN ('entregue', 'cancelado')
ORDER BY saldo_devedor DESC;

-- ---------------------------------------------------------------------
-- Consulta 6 - Camisas mais vendidas
-- Soma as unidades pedidas de cada camisa e o faturamento, ignorando
-- pedidos cancelados. Agrupei pelo id do produto (e não só pelo nome do
-- clube) para não misturar camisas diferentes do mesmo clube, como a
-- versão torcedor e a versão jogador. Só aparecem camisas que já foram
-- vendidas.
-- ---------------------------------------------------------------------
SELECT pr.id_produto,
       pr.clube_selecao,
       pr.temporada,
       pr.modelo,
       pr.versao,
       SUM(i.quantidade) AS unidades_vendidas,
       SUM(i.quantidade * i.preco_unitario) AS faturamento
FROM produtos pr
JOIN itens_pedido i ON i.id_produto = pr.id_produto
JOIN pedidos p      ON p.id_pedido  = i.id_pedido
WHERE p.status <> 'cancelado'
GROUP BY pr.id_produto, pr.clube_selecao, pr.temporada, pr.modelo, pr.versao
ORDER BY unidades_vendidas DESC, faturamento DESC;

-- ---------------------------------------------------------------------
-- Consulta 7 - Movimento por fornecedor
-- Mostra todos os fornecedores, inclusive os que não tiveram vendas
-- (por isso usei LEFT JOIN). Para cada um traz em quantos pedidos
-- diferentes ele aparece e quantas camisas foram vendidas, além do
-- prazo médio de entrega para comparar. O filtro de pedidos cancelados
-- ficou dentro do JOIN entre parênteses, e não no WHERE, porque no WHERE
-- ele eliminaria os fornecedores sem vendas e o LEFT JOIN perderia o
-- efeito. COUNT(DISTINCT ...) evita contar o mesmo pedido duas vezes
-- quando ele tem mais de uma camisa do mesmo fornecedor. Quem não vendeu
-- nada aparece com 0 pedidos e 0 unidades.
-- ---------------------------------------------------------------------
SELECT f.id_fornecedor,
       f.nome AS fornecedor,
       f.pais,
       f.ativo,
       f.prazo_medio_dias,
       COUNT(DISTINCT v.id_pedido) AS qtd_pedidos,
       COALESCE(SUM(v.quantidade), 0) AS unidades_vendidas
FROM fornecedores f
LEFT JOIN produtos pr ON pr.id_fornecedor = f.id_fornecedor
LEFT JOIN (itens_pedido v
           JOIN pedidos p ON p.id_pedido = v.id_pedido
                         AND p.status <> 'cancelado')
       ON v.id_produto = pr.id_produto
GROUP BY f.id_fornecedor, f.nome, f.pais, f.ativo, f.prazo_medio_dias
ORDER BY unidades_vendidas DESC, f.nome;

-- ---------------------------------------------------------------------
-- Consulta 8 - Pedidos atrasados
-- Pedidos que já deveriam ter chegado (previsão menor que a data de
-- hoje) mas continuam encomendados ou em trânsito. A diferença entre
-- duas datas no PostgreSQL já retorna o número de dias. Como usa a data
-- de hoje (CURRENT_DATE), o resultado muda conforme o dia em que o
-- script é executado.
-- ---------------------------------------------------------------------
SELECT p.id_pedido,
       c.nome AS cliente,
       p.status,
       p.previsao_entrega,
       CURRENT_DATE - p.previsao_entrega AS dias_de_atraso
FROM pedidos p
JOIN clientes c ON c.id_cliente = p.id_cliente
WHERE p.previsao_entrega < CURRENT_DATE
  AND p.status IN ('encomendado', 'em_transito')
ORDER BY dias_de_atraso DESC;

-- ---------------------------------------------------------------------
-- Consulta 9 - Pagamentos por forma e situação
-- Quantos pagamentos e quanto dinheiro existe em cada forma de
-- pagamento (pix, cartão, boleto), separando o que já foi confirmado
-- do que ainda está pendente. Assim dá para ver, por exemplo, que o
-- dinheiro dos boletos ainda não entrou.
-- ---------------------------------------------------------------------
SELECT forma,
       situacao,
       COUNT(*) AS qtd_pagamentos,
       SUM(valor) AS total
FROM pagamentos
GROUP BY forma, situacao
ORDER BY forma, situacao;

-- ---------------------------------------------------------------------
-- Consulta 10 - Quantidade de pedidos por status
-- Visão geral do andamento da loja: quantos pedidos estão em cada etapa.
-- ---------------------------------------------------------------------
SELECT status,
       COUNT(*) AS qtd_pedidos
FROM pedidos
GROUP BY status
ORDER BY qtd_pedidos DESC, status;

-- Fim do script
