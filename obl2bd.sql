CREATE TABLE Users ( 
	id number primary key, 
    userName varchar(50) not null, 
    publicName varchar(50) not null unique,  
    password varchar(50) not null, 
    bio varchar(250), 
    birthDate date not null, 
    photoId number, 
    bannerId number, 
    userLevel varchar(50) not null CHECK(userLevel in ('Streamer', 'Afiliado', 'Partner')), 
	createdAt timestamp not null, 
    bitsAvailable number 
);

CREATE TABLE Photos ( 
	id number primary key, 
    imagePath varchar(250), 
    imageSize number not null CHECK(imageSize <= 10), 
    imageFormat varchar(5) CHECK(imageFormat IN ('JPEG', 'PNG', 'GIF')) 
);

CREATE TABLE Banners ( 
	id number primary key, 
    imagePath varchar(250), 
    imageSize number not null CHECK(imageSize <= 10), 
    imageFormat varchar(5) CHECK(imageFormat IN ('JPEG', 'PNG', 'GIF')) 
);

CREATE TABLE Recoveries ( 
	userId number primary key, 
    type varchar(1) not null CHECK(type in ('M', 'P')),  -- 'M' para mail, 'P' para telefono
    data varchar(50) not null, 
    foreign key(userId) references Users(id) 
);

CREATE TABLE Follows ( 
	fromUserId number, 
    toUserId number, 
    primary key(fromUserId, toUserId), 
    foreign key(fromUserId) references Users(id), 
    foreign key(toUserId) references Users(id) 
);

CREATE TABLE TransactionTypes ( 
	id number primary key, 
    bits number not null, 
    price number not null 
);

CREATE TABLE Transactions ( 
	userId number not null, 
    transactionTypeId number not null, 
    formOfPayment varchar(50) CHECK(formOfPayment IN ('Crédito', 'Paypal')), 
    createdAt timestamp not null, 
    primary key(userId, createdAt), 
    foreign key(userId) references Users(id), 
    foreign key(transactionTypeId) references TransactionTypes(id) 
);

CREATE TABLE Achievements ( 
	id number primary key, 
    description varchar(50) not null 
);

CREATE TABLE UserAchievements ( 
	userId number,
    achievementId number,
    primary key(userId, achievementId),
    foreign key(userId) references Users(id),
    foreign key(achievementId) references Achievements(id)
);

CREATE TABLE SubscriptionCountryPrices ( 
	country varchar(50) primary key, 
    price number not null CHECK(price > 0)
);

CREATE TABLE Subscriptions ( 
	fromUserId number not null, 
    country varchar(50) not null, 
    toUserId number not null, 
    createdAt timestamp not null, 
    formOfPayment varchar(50) not null, 
    months number not null CHECK(months > 0),
    autoRenew varchar(1) not null CHECK(autoRenew in ('Y', 'N')),
    primary key(fromUserId, toUserId, createdAt), 
    foreign key(fromUserId) references Users(id), 
    foreign key(toUserId) references Users(id), 
    foreign key(country) references SubscriptionCountryPrices(country) 
);

CREATE TABLE UserPaymentMethod ( 
	userId number primary key, 
    formOfPayment varchar(50), 
    foreign key(userId) references Users(id) 
);

CREATE TABLE Donations( 
    fromUserId number not null, 
    toUserId number not null, 
    bitsDonated number not null, 
    fecha timestamp not null, 
    primary key(fromUserId, toUserId, fecha), 
    foreign key(fromUserId) references Users(id), 
    foreign key(toUserId) references Users(id) 
);

CREATE or replace TRIGGER canCreateAccount  
BEFORE INSERT ON Users  
FOR EACH ROW  
BEGIN
    IF (trunc(months_between(SYSDATE, :new.birthDate)/12) < 13) THEN  
        RAISE_APPLICATION_ERROR(-20001, 'El usuario debe tener al menos 13 años para poder registrarse');  
    END IF;
    IF (:new.userLevel <> 'Streamer') THEN
        RAISE_APPLICATION_ERROR(-20001, 'El usuario debe iniciar con nivel streamer para poder registrarse');
    END IF;
END; 

CREATE or replace TRIGGER toUserCanReceiveSubscriptions  
BEFORE INSERT OR UPDATE ON Subscriptions
FOR EACH ROW  
DECLARE  
    level VARCHAR(50);  
BEGIN  
    select u.userLevel into level from Users u  
    where u.id = :new.toUserId;  
    IF level NOT IN ('Afiliado','Partner') THEN  
        RAISE_APPLICATION_ERROR(-20001, 'No se permiten suscripciones a canales que no sean de tipo Afiliado o Partner');  
    END IF;  
END;
 
CREATE or replace TRIGGER donateBits  
BEFORE INSERT OR UPDATE ON Donations  
FOR EACH ROW  
DECLARE  
    bits number;  
BEGIN  
    select u.bitsAvailable into bits from Users u  
    where u.id = :new.fromUserId;  
    IF bits < :new.bitsDonated THEN  
        RAISE_APPLICATION_ERROR(-20001, 'El usuario no tiene suficientes bits para realizar esta donación');  
    END IF;
    update Users u set u.bitsAvailable = u.bitsAvailable - :new.bitsDonated where u.id = :new.fromUserId;  
END; 

CREATE or replace TRIGGER addBits
AFTER INSERT OR UPDATE ON Transactions
FOR EACH ROW
DECLARE 
    bits number;
BEGIN
    select tt.bits into bits from TransactionTypes tt where tt.id = :new.transactionTypeId;
    UPDATE Users SET bitsAvailable = bitsAvailable + bits WHERE id = :new.userId;
END;

CREATE or replace TRIGGER addPaymentMethod
AFTER INSERT OR UPDATE ON Subscriptions
FOR EACH ROW
BEGIN
    INSERT INTO UserPaymentMethod values(:new.fromUserId, :new.formOfPayment);
EXCEPTION
    WHEN DUP_VAL_ON_INDEX THEN
        UPDATE UserPaymentMethod SET formOfPayment = :new.formOfPayment WHERE userId = :new.fromUserId;
END;
 
--req1:
 
CREATE FUNCTION req1 (fechaInicio DATE, fechaFin DATE, userId number) RETURN NUMBER IS 
BEGIN 
    DECLARE  
        cantDonaciones number; 
        cantBits number; 
    BEGIN 
        SELECT count(*), sum(bitsDonated) 
        INTO cantDonaciones, cantBits 
        FROM Donations d 
        WHERE d.toUserId = userId AND d.fecha > fechaInicio AND d.fecha < fechaFin; 
        DBMS_OUTPUT.PUT_LINE('Amount of donations: ' || TO_CHAR(cantDonaciones) || ' Total of Bits: ' || TO_CHAR(cantBits)); 
        RETURN cantBits; 
    END; 
END; 

-- req2:

CREATE or replace PROCEDURE req2 (cant number) IS
cursor c_users is
    select u.publicName, count(*) as cantSuscriptores
    from Users u, Subscriptions s
    where u.id = s.toUserId and ADD_MONTHS(s.createdAt, s.months) > SYSDATE
    group by u.publicName
    order by cantSuscriptores desc
    fetch first cant rows only;
BEGIN
    for c_users_row in c_users loop
        DBMS_OUTPUT.PUT_LINE(c_users_row.publicName || ' has ' || c_users_row.cantSuscriptores || ' subscribers');
    end loop;
END;

        
-- req3:

create or replace procedure req3 is
    cursor c_suscripciones is
        select s.fromUserId, s.country, s.toUserId, s.createdAt, s.months, upm.formOfPayment
        from Subscriptions s, UserPaymentMethod upm
        where to_date(ADD_MONTHS(s.createdAt, s.months), 'DD-MM-YYYY') = to_date(SYSDATE, 'DD-MM-YYYY') and s.fromUserId = upm.userId and s.autoRenew = 'Y';
    begin
        for suscripcion in c_suscripciones loop
            insert into Subscriptions values (suscripcion.fromUserId, suscripcion.country, suscripcion.toUserId, SYSDATE, suscripcion.formOfPayment, suscripcion.months, 'Y');
        end loop;
    end;


-- Datos de prueba 

-- Usuarios:

-- Validos:

insert into Users values (1, 'Juan', 'Juanito', 'Password1.', null, to_date('17-05-2000', 'DD-MM-YYYY'), null, null, 'Streamer', SYSDATE, 0);
insert into Users values (2, 'Rodrigo', 'Ro', 'Password1.', 'Bienvenidos a mi canal!', to_date('17-05-2000', 'DD-MM-YYYY'), null, null, 'Partner', SYSDATE, 0);
insert into Users values (3, 'Jaime', 'Jimmy', 'Password1.', '', to_date('17-05-2000', 'DD-MM-YYYY'), null, null, 'Afiliado', SYSDATE, 0);
insert into Users values (4, 'Ana', 'Anita', 'Password1.', 'Hola, soy Anita :)', to_date('17-05-2000', 'DD-MM-YYYY'), null, null, 'Streamer', SYSDATE, 0);

--update user 2 to be a partner
update Users set userLevel = 'Partner' where id = 2;
--subscribe user 1 to user 2
insert into Subscriptions values (1, 'Argentina', 2, to_date('17-05-2000', 'DD-MM-YYYY'), 'Y');

-- Invalidos:

-- Devido a que no es mayor a 13 años
insert into Users values (5, 'Agustin', 'Agus', 'Password1.', null, to_date('17-05-2010', 'DD-MM-YYYY'), null, null, 'Streamer', SYSDATE, 0);
-- Devido a que ya existe uno con ese publicName
insert into Users values (5, 'Juan', 'Juanito', 'Password1.', null, to_date('17-05-2000', 'DD-MM-YYYY'), null, null, 'Streamer', SYSDATE, 0);
-- Devido a que ya existe uno con ese id
insert into Users values (1, 'Juana', 'Juanita', 'Password1.', null, to_date('17-05-2000', 'DD-MM-YYYY'), null, null, 'Streamer', SYSDATE, 0);
-- Devido a que su userLevel no es valido
insert into Users values (5, 'Nicolas', 'Nico', 'Password1.', null, to_date('17-05-2000', 'DD-MM-YYYY'), null, null, 'Invalid Level', SYSDATE, 0);

-- Photos:

-- Validos:

insert into Photos values (1, 'c:/misFotos/FotoDePerfil', 9, 'PNG');
insert into Photos values (2, 'c:/misFotos/FotoDePerfilAlternativa', 9, 'JPEG');
insert into Photos values (3, 'c:/misFotos/GifDePerfil', 9, 'GIF');

-- Invalidos:

-- Devido a que el tamaño del archivo es mayor a 10MB
insert into Photos values (4, 'c:/misFotos/FotoDePerfil', 11, 'PNG');
-- Devido a que el formato del archivo no es valido
insert into Photos values (5, 'c:/misFotos/FotoDePerfil', 9, 'SVG');


-- Banners:

-- Validos:

insert into Banners values (1, 'c:/misBanners/BannerParaMiCuenta', 9, 'PNG');
insert into Banners values (2, 'c:/misBanners/BannerAlternativo', 9, 'JPEG');
insert into Banners values (3, 'c:/misBanners/BannerGif', 9, 'GIF');

-- Invalidos:

-- Devido a que el tamaño del archivo es mayor a 10MB
insert into Banners values (4, 'c:/misBanners/BannerParaMiCuenta', 11, 'PNG');
-- Devido a que el formato del archivo no es valido
insert into Banners values (5, 'c:/misBanners/BannerParaMiCuenta', 9, 'SVG');

-- Recoveries:

-- Validos:

insert into Recoveries values (1, 'P', '098-765-432');
insert into Recoveries values (2, 'M', 'rodrigo@gmail.com');

-- Invalidos:

-- Devido a que el tipo de dato no es valido
insert into Recoveries values (3, 'A', '098-765-432');

-- Follows:

-- Validos:

insert into Follows values (1, 2);
insert into Follows values (1, 3);

-- Invalidos:

-- Devido a que el usuario no existe
insert into Follows values (1, 5);
-- Devido a que el usuario ya sigue al otro
insert into Follows values (1, 2);


-- TransactionTypes:
-- Esta tabla es de datos creados por el negocio, no se debe modificar

insert into TransactionTypes values (1, 300, 3.00);
insert into TransactionTypes values (2, 5000, 64.40);
insert into TransactionTypes values (3, 25000, 308.00);

-- Transactions:

-- Validos:

insert into Transactions values (1, 2, 'Paypal', SYSDATE);
insert into Transactions values (2, 3, 'Crédito', SYSDATE);

-- Invalidos:

-- Devido a que el tipo de transacción no es valido
insert into Transactions values (3, 5, 'Paypal', SYSDATE);
-- Devido a que la forma de pago no es valida
insert into Transactions values (4, 2, 'Débito', SYSDATE);

-- SubscriptionCountryPrices

-- Validos:

insert into SubscriptionCountryPrices values ('Uruguay', 5);
insert into SubscriptionCountryPrices values ('Argentina', 6);

-- Subscriptions:

-- Validos:

insert into Subscriptions values (1, 'Argentina', 2, to_date('18-05-2022', 'DD-MM-YYYY'), 'Paypal', 1, 'Y');
insert into Subscriptions values (1, 'Argentina', 2, to_date('19-05-2022', 'DD-MM-YYYY'), 'Paypal', 1, 'N');

-- Invalidos:

-- Devido a que el usuario no existe
insert into Subscriptions values (3, 'Argentina', 5, SYSDATE, 'Paypal', 12);
-- Devido a que el usuario ya tiene una suscripcion
insert into Subscriptions values (1, 'Argentina', 2, SYSDATE, 'Paypal', 12);
-- Devido a que el tipo de pago no es valido
insert into Subscriptions values (4, 'Argentina', 2, SYSDATE, 'Débito', 12);
-- Devido a que el userLevel no es valido
insert into Subscriptions values (1, 'Argentina', 4, SYSDATE, 'Paypal', 12);

-- PaymentMethods:

-- Validos:

insert into UserPaymentMethods values (1, 'Paypal');