CREATE DATABASE ESCOLA;
USE ESCOLA;

CREATE TABLE ALUNO (
    IDALUNO INT PRIMARY KEY AUTO_INCREMENT,
    NOME VARCHAR(50) NOT NULL,
    DATA_NASC DATE NOT NULL,
    SEXO ENUM('M','F') NOT NULL
);

CREATE TABLE TELEFONE (
    IDTELEFONE INT PRIMARY KEY AUTO_INCREMENT,
    TIPO ENUM('CEL','RES','COM') NOT NULL,
    NUMERO VARCHAR(15),
    ID_ALUNO INT
);

CREATE TABLE TURMA (
    IDTURMA INT PRIMARY KEY AUTO_INCREMENT,
    NOME_TURMA VARCHAR(20) NOT NULL UNIQUE,
    ANO LETIVO INT
);

CREATE TABLE PROFESSOR (
    IDPROF INT PRIMARY KEY AUTO_INCREMENT,
    NOME VARCHAR(50) NOT NULL
);

CREATE TABLE DISCIPLINA (
    IDDISCIPLINA INT PRIMARY KEY AUTO_INCREMENT,
    NOME_DISCIPLINA VARCHAR(50) NOT NULL UNIQUE
);

CREATE TABLE ALUNO_TURMA (
    ID_ALUNO INT,
    ID_TURMA INT,
    PRIMARY KEY(ID_ALUNO, ID_TURMA)
);

CREATE TABLE PROFESSOR_DISCIPLINA (
    ID_PROF INT,
    ID_DISCIPLINA INT,
    PRIMARY KEY(ID_PROF, ID_DISCIPLINA)
);

------- CONSTRAINTS --------

ALTER TABLE TELEFONE
ADD CONSTRAINT FK_TEL_ALUNO
FOREIGN KEY (ID_ALUNO) REFERENCES ALUNO(IDALUNO);

ALTER TABLE ALUNO_TURMA
ADD CONSTRAINT FK_AL_TURMA
FOREIGN KEY (ID_TURMA) REFERENCES TURMA(IDTURMA);

ALTER TABLE ALUNO_TURMA
ADD CONSTRAINT FK_AL_ALUNO
FOREIGN KEY (ID_ALUNO) REFERENCES ALUNO(IDALUNO);

ALTER TABLE PROFESSOR_DISCIPLINA
ADD CONSTRAINT FK_PD_PROF
FOREIGN KEY (ID_PROF) REFERENCES PROFESSOR(IDPROF);

ALTER TABLE PROFESSOR_DISCIPLINA
ADD CONSTRAINT FK_PD_DISC
FOREIGN KEY (ID_DISCIPLINA) REFERENCES DISCIPLINA(IDDISCIPLINA);

------ SELECTS ------

SELECT 
    A.NOME AS ALUNO,
    T.NOME_TURMA,
    T.ANO
FROM 
    ALUNO A
JOIN 
    ALUNO_TURMA AT ON A.IDALUNO = AT.ID_ALUNO
JOIN 
    TURMA T ON AT.ID_TURMA = T.IDTURMA;



SELECT 
    P.NOME AS PROFESSOR,
    D.NOME_DISCIPLINA
FROM 
    PROFESSOR P
JOIN 
    PROFESSOR_DISCIPLINA PD ON P.IDPROF = PD.ID_PROF
JOIN 
    DISCIPLINA D ON PD.ID_DISCIPLINA = D.IDDISCIPLINA;



SELECT 
    T.NOME_TURMA,
    COUNT(AT.ID_ALUNO) AS QTD_ALUNOS
FROM 
    TURMA T
LEFT JOIN 
    ALUNO_TURMA AT ON T.IDTURMA = AT.ID_TURMA
GROUP BY 
    T.NOME_TURMA;



------- DELETES-------

DELETE FROM ALUNO
WHERE IDALUNO NOT IN (
    SELECT DISTINCT ID_ALUNO FROM ALUNO_TURMA
);

DELETE FROM DISCIPLINA
WHERE IDDISCIPLINA NOT IN (
    SELECT DISTINCT ID_DISCIPLINA FROM PROFESSOR_DISCIPLINA
);

DELETE FROM TURMA
WHERE IDTURMA NOT IN (
    SELECT DISTINCT ID_TURMA FROM ALUNO_TURMA
);


------- ALTER TABLE'S -------

ALTER TABLE ALUNO
ADD EMAIL VARCHAR(100);

ALTER TABLE DISCIPLINA
MODIFY NOME_DISCIPLINA VARCHAR(80);

ALTER TABLE TURMA
ADD TURNO ENUM('MANHÃ', 'TARDE', 'NOITE');

