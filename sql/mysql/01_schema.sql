CREATE DATABASE IF NOT EXISTS kyc_aml_portafolio;
USE kyc_aml_portafolio;

CREATE TABLE paises (
    pais_id             INT AUTO_INCREMENT PRIMARY KEY,
    nombre_pais         VARCHAR(80)  NOT NULL UNIQUE,
    codigo_iso3         CHAR(3)      NOT NULL UNIQUE,
    es_sancionado_ofac  BOOLEAN      NOT NULL DEFAULT FALSE,
    nivel_riesgo_pais   VARCHAR(10)  NOT NULL DEFAULT 'Bajo'
        CHECK (nivel_riesgo_pais IN ('Bajo','Medio','Alto')),
    observaciones       VARCHAR(200)
);

CREATE TABLE clientes (
    cliente_id                      INT AUTO_INCREMENT PRIMARY KEY,
    tipo_persona                     VARCHAR(6)  NOT NULL CHECK (tipo_persona IN ('Fisica','Moral')),
    nombre_completo                   VARCHAR(150) NOT NULL,
    fecha_nacimiento_constitucion       DATE NOT NULL,
    fecha_alta                       DATETIME NOT NULL,
    canal_alta                       VARCHAR(20) NOT NULL CHECK (canal_alta IN ('Sucursal','Digital','Ejecutivo')),
    ciudad                          VARCHAR(60) NOT NULL,
    estado_republica                   VARCHAR(60) NOT NULL,
    pais_id                         INT NOT NULL,
    ocupacion_giro                    VARCHAR(80) NOT NULL,
    ingreso_mensual_declarado_mxn        DECIMAL(14,2) NOT NULL,
    es_pep                          BOOLEAN NOT NULL DEFAULT FALSE,
    nivel_riesgo_kyc_onboarding          VARCHAR(10) NOT NULL DEFAULT 'Bajo' CHECK (nivel_riesgo_kyc_onboarding IN ('Bajo','Medio','Alto')),
    estatus_cliente                   VARCHAR(15) NOT NULL DEFAULT 'Activo' CHECK (estatus_cliente IN ('Activo','Inactivo','En Revision','Bloqueado')),
    FOREIGN KEY (pais_id) REFERENCES paises(pais_id)
);

CREATE TABLE cuentas (
    cuenta_id           INT AUTO_INCREMENT PRIMARY KEY,
    cliente_id           INT NOT NULL,
    numero_cuenta         VARCHAR(20) NOT NULL UNIQUE,
    tipo_cuenta          VARCHAR(15) NOT NULL CHECK (tipo_cuenta IN ('Ahorro','Cheques','Inversion','Empresarial')),
    fecha_apertura        DATETIME NOT NULL,
    sucursal             VARCHAR(60) NOT NULL,
    estado_cuenta         VARCHAR(15) NOT NULL DEFAULT 'Activa' CHECK (estado_cuenta IN ('Activa','Inactiva','Cancelada')),
    FOREIGN KEY (cliente_id) REFERENCES clientes(cliente_id)
);

CREATE TABLE personas_morales_socios (
    socio_id                  INT AUTO_INCREMENT PRIMARY KEY,
    cliente_id                 INT NOT NULL,
    nombre_socio                VARCHAR(150) NOT NULL,
    porcentaje_participacion      DECIMAL(5,2) NOT NULL CHECK (porcentaje_participacion BETWEEN 0 AND 100),
    es_beneficiario_final_ubo      BOOLEAN NOT NULL DEFAULT FALSE,
    pais_nacionalidad_id           INT NOT NULL,
    en_lista_negra              BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (cliente_id) REFERENCES clientes(cliente_id),
    FOREIGN KEY (pais_nacionalidad_id) REFERENCES paises(pais_id)
);

CREATE TABLE contacto_dispositivo_cliente (
    registro_id       INT AUTO_INCREMENT PRIMARY KEY,
    cliente_id         INT NOT NULL,
    telefono          VARCHAR(15) NOT NULL,
    correo            VARCHAR(120) NOT NULL,
    dispositivo_id      VARCHAR(40) NOT NULL,
    ip_registro        VARCHAR(45) NOT NULL,
    FOREIGN KEY (cliente_id) REFERENCES clientes(cliente_id)
);

CREATE TABLE transacciones (
    transaccion_id       BIGINT AUTO_INCREMENT PRIMARY KEY,
    cuenta_id             INT NOT NULL,
    fecha_hora            DATETIME NOT NULL,
    monto_mxn             DECIMAL(14,2) NOT NULL CHECK (monto_mxn > 0),
    tipo_transaccion        VARCHAR(30) NOT NULL CHECK (tipo_transaccion IN
                             ('Deposito Efectivo','Retiro Efectivo','Transferencia SPEI','Transferencia Internacional','Pago Tarjeta','Deposito Cheque')),
    canal                 VARCHAR(10) NOT NULL CHECK (canal IN ('App','Sucursal','Cajero','Web')),
    pais_origen_id          INT NOT NULL,
    pais_destino_id          INT NOT NULL,
    es_internacional          BOOLEAN NOT NULL DEFAULT FALSE,
    ip_origen             VARCHAR(45),
    FOREIGN KEY (cuenta_id) REFERENCES cuentas(cuenta_id),
    FOREIGN KEY (pais_origen_id) REFERENCES paises(pais_id),
    FOREIGN KEY (pais_destino_id) REFERENCES paises(pais_id)
);

CREATE TABLE intentos_acceso (
    intento_id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    cliente_id       INT NOT NULL,
    fecha_hora       DATETIME NOT NULL,
    exitoso         BOOLEAN NOT NULL,
    tipo_intento     VARCHAR(30) NOT NULL CHECK (tipo_intento IN ('Login','Cambio Contrasena','Transferencia Alto Monto')),
    ip_origen       VARCHAR(45) NOT NULL,
    dispositivo_id    VARCHAR(40) NOT NULL,
    FOREIGN KEY (cliente_id) REFERENCES clientes(cliente_id)
);

CREATE TABLE ground_truth_casos_riesgo (
    caso_id       INT AUTO_INCREMENT PRIMARY KEY,
    tipo_entidad    VARCHAR(15) NOT NULL CHECK (tipo_entidad IN ('Cliente','Cuenta','Socio')),
    entidad_id     INT NOT NULL,
    tipo_riesgo     VARCHAR(40) NOT NULL,
    descripcion    VARCHAR(200) NOT NULL
);

CREATE TABLE casos_revision_kyc (
    caso_id                      BIGINT AUTO_INCREMENT PRIMARY KEY,
    tipo_entidad                   VARCHAR(15) NOT NULL,
    entidad_id                    INT NOT NULL,
    cliente_id                    INT NOT NULL,
    tipo_alerta                   VARCHAR(40) NOT NULL,
    detalle_alerta                  VARCHAR(300),
    fecha_generacion                DATETIME NOT NULL,
    analista_asignado               VARCHAR(60) NOT NULL,
    fecha_asignacion                 DATETIME NOT NULL,
    fecha_cierre                   DATETIME,
    horas_invertidas                DECIMAL(6,2),
    prioridad                     VARCHAR(10) NOT NULL CHECK (prioridad IN ('Baja','Media','Alta','Critica')),
    resultado                     VARCHAR(35) NOT NULL CHECK (resultado IN ('Falso Positivo','Cliente Contactado - Aclarado','Escalado a EDD','Confirmado - Aviso a UIF','En Proceso')),
    es_caso_verdadero_ground_truth      BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (cliente_id) REFERENCES clientes(cliente_id)
);
