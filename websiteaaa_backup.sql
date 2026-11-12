--
-- PostgreSQL database dump
--

\restrict gbqM4nDvOBtGIxeaSho1ZjgVQzRatwEcLMObZ4rVhMKE5LilNq1PwSPctSIkvvp

-- Dumped from database version 17.11
-- Dumped by pg_dump version 17.11

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citext; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citext WITH SCHEMA public;


--
-- Name: EXTENSION citext; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION citext IS 'data type for case-insensitive character strings';


--
-- Name: has_course_access(public.citext, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_course_access(p_username public.citext, p_course bigint) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    SELECT EXISTS (SELECT 1 FROM enrollments
                   WHERE student_username = p_username AND course_id = p_course AND status = 'Approved')
       AND has_paid_access(p_username, p_course);
$$;


--
-- Name: has_paid_access(public.citext, bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.has_paid_access(p_username public.citext, p_course bigint) RETURNS boolean
    LANGUAGE sql STABLE
    AS $$
    SELECT COALESCE((SELECT price_amount = 0 FROM courses WHERE id = p_course), FALSE)
        OR EXISTS (SELECT 1 FROM payments
                   WHERE student_username = p_username AND course_id = p_course AND status = 'Paid');
$$;


--
-- Name: trg_certificate_eligibility(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_certificate_eligibility() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NOT has_course_access(NEW.student_username, NEW.course_id) THEN
        RAISE EXCEPTION 'Certificate refused: enrollment not approved or course not paid'
            USING ERRCODE = 'P0001';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM quizzes q JOIN modules m ON m.id = q.module_id WHERE m.course_id = NEW.course_id) THEN
        RAISE EXCEPTION 'Certificate refused: course has no quizzes' USING ERRCODE = 'P0001';
    END IF;
    IF EXISTS (
        SELECT 1 FROM quizzes q JOIN modules m ON m.id = q.module_id
        WHERE m.course_id = NEW.course_id
          AND NOT EXISTS (SELECT 1 FROM quiz_attempts a
                          WHERE a.quiz_id = q.id AND a.student_username = NEW.student_username AND a.passed)
    ) THEN
        RAISE EXCEPTION 'Certificate refused: not all quizzes passed' USING ERRCODE = 'P0001';
    END IF;
    RETURN NEW;
END $$;


--
-- Name: trg_require_course_access(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_require_course_access() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_course BIGINT;
BEGIN
    IF TG_TABLE_NAME = 'quiz_attempts' THEN
        SELECT m.course_id INTO v_course FROM quizzes q JOIN modules m ON m.id = q.module_id WHERE q.id = NEW.quiz_id;
        IF NOT has_course_access(NEW.student_username, v_course) THEN
            RAISE EXCEPTION 'Course access denied: enrollment not approved or course not paid'
                USING ERRCODE = 'P0001';
        END IF;
    ELSIF TG_TABLE_NAME = 'material_progress' THEN
        SELECT m.course_id INTO v_course FROM materials t JOIN modules m ON m.id = t.module_id WHERE t.id = NEW.material_id;
        IF NOT has_course_access(NEW.student_username, v_course) THEN
            RAISE EXCEPTION 'Course access denied: enrollment not approved or course not paid'
                USING ERRCODE = 'P0001';
        END IF;
    END IF;
    RETURN NEW;
END $$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: achievements; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.achievements (
    id bigint NOT NULL,
    student_username public.citext NOT NULL,
    course_id bigint NOT NULL,
    title text NOT NULL,
    details text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: achievements_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.achievements_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: achievements_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.achievements_id_seq OWNED BY public.achievements.id;


--
-- Name: answer_options; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.answer_options (
    id bigint NOT NULL,
    question_id bigint NOT NULL,
    text text NOT NULL,
    is_correct boolean DEFAULT false NOT NULL,
    "position" integer NOT NULL,
    CONSTRAINT answer_options_position_check CHECK (("position" > 0)),
    CONSTRAINT answer_options_text_check CHECK ((length(btrim(text)) > 0))
);


--
-- Name: answer_options_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.answer_options_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: answer_options_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.answer_options_id_seq OWNED BY public.answer_options.id;


--
-- Name: attempt_answers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attempt_answers (
    attempt_id bigint NOT NULL,
    quiz_id bigint NOT NULL,
    question_id bigint NOT NULL,
    option_id bigint NOT NULL
);


--
-- Name: audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.audit_log (
    id bigint NOT NULL,
    "timestamp" timestamp with time zone DEFAULT now() NOT NULL,
    event_type text NOT NULL,
    action text NOT NULL,
    result text NOT NULL,
    username text,
    resource text,
    details text,
    prev_hash bytea NOT NULL,
    entry_hash bytea NOT NULL
);


--
-- Name: audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.audit_log_id_seq OWNED BY public.audit_log.id;


--
-- Name: certificate_no_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.certificate_no_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: certificates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.certificates (
    id bigint NOT NULL,
    certificate_no text DEFAULT ('CERT-'::text || lpad((nextval('public.certificate_no_seq'::regclass))::text, 8, '0'::text)) NOT NULL,
    student_username public.citext NOT NULL,
    course_id bigint NOT NULL,
    issued_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: certificates_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.certificates_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: certificates_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.certificates_id_seq OWNED BY public.certificates.id;


--
-- Name: comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comments (
    id bigint NOT NULL,
    student_username public.citext NOT NULL,
    author_username public.citext NOT NULL,
    text text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: comments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.comments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: comments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.comments_id_seq OWNED BY public.comments.id;


--
-- Name: course_tutors; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.course_tutors (
    course_id bigint NOT NULL,
    tutor_username public.citext NOT NULL,
    assigned_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: courses; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.courses (
    id bigint NOT NULL,
    name text NOT NULL,
    slug text,
    description text DEFAULT ''::text NOT NULL,
    cover_url text,
    is_published boolean DEFAULT true NOT NULL,
    price_amount numeric(10,2) DEFAULT 0 NOT NULL,
    currency character(3) DEFAULT 'USD'::bpchar NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT courses_price_nonneg CHECK ((price_amount >= (0)::numeric))
);


--
-- Name: courses_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.courses_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: courses_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.courses_id_seq OWNED BY public.courses.id;


--
-- Name: enrollments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.enrollments (
    id bigint NOT NULL,
    student_username public.citext NOT NULL,
    course_id bigint NOT NULL,
    status text DEFAULT 'Pending'::text NOT NULL,
    decided_by public.citext,
    requested_at timestamp with time zone DEFAULT now() NOT NULL,
    decided_at timestamp with time zone,
    CONSTRAINT enrollments_status_check CHECK ((status = ANY (ARRAY['Pending'::text, 'Approved'::text, 'Rejected'::text])))
);


--
-- Name: enrollments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.enrollments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: enrollments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.enrollments_id_seq OWNED BY public.enrollments.id;


--
-- Name: material_progress; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.material_progress (
    student_username public.citext NOT NULL,
    material_id bigint NOT NULL,
    completed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: materials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.materials (
    id bigint NOT NULL,
    module_id bigint NOT NULL,
    kind text NOT NULL,
    title text NOT NULL,
    body text,
    resource_url text,
    "position" integer NOT NULL,
    created_by public.citext,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT materials_check CHECK ((((kind = 'text'::text) AND (NULLIF(btrim(body), ''::text) IS NOT NULL)) OR ((kind <> 'text'::text) AND (NULLIF(btrim(resource_url), ''::text) IS NOT NULL)))),
    CONSTRAINT materials_kind_check CHECK ((kind = ANY (ARRAY['text'::text, 'video'::text, 'audio'::text, 'image'::text, 'link'::text]))),
    CONSTRAINT materials_position_check CHECK (("position" > 0)),
    CONSTRAINT materials_title_check CHECK ((length(btrim(title)) > 0))
);


--
-- Name: materials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.materials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: materials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.materials_id_seq OWNED BY public.materials.id;


--
-- Name: modules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.modules (
    id bigint NOT NULL,
    course_id bigint NOT NULL,
    title text NOT NULL,
    "position" integer NOT NULL,
    CONSTRAINT modules_position_check CHECK (("position" > 0)),
    CONSTRAINT modules_title_check CHECK ((length(btrim(title)) > 0))
);


--
-- Name: modules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.modules_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: modules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.modules_id_seq OWNED BY public.modules.id;


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id bigint NOT NULL,
    student_username public.citext NOT NULL,
    course_id bigint NOT NULL,
    amount numeric(10,2) NOT NULL,
    currency character(3) DEFAULT 'USD'::bpchar NOT NULL,
    status text DEFAULT 'Pending'::text NOT NULL,
    provider text,
    provider_ref text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    paid_at timestamp with time zone,
    CONSTRAINT payments_amount_check CHECK ((amount >= (0)::numeric)),
    CONSTRAINT payments_check CHECK (((status = ANY (ARRAY['Paid'::text, 'Refunded'::text])) = (paid_at IS NOT NULL))),
    CONSTRAINT payments_status_check CHECK ((status = ANY (ARRAY['Pending'::text, 'Paid'::text, 'Failed'::text, 'Refunded'::text])))
);


--
-- Name: payments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.payments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.payments_id_seq OWNED BY public.payments.id;


--
-- Name: permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.permissions (
    id bigint NOT NULL,
    name text NOT NULL
);


--
-- Name: permissions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.permissions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: permissions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.permissions_id_seq OWNED BY public.permissions.id;


--
-- Name: questions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.questions (
    id bigint NOT NULL,
    quiz_id bigint NOT NULL,
    text text NOT NULL,
    kind text NOT NULL,
    "position" integer NOT NULL,
    CONSTRAINT questions_kind_check CHECK ((kind = ANY (ARRAY['single'::text, 'multiple'::text, 'true_false'::text]))),
    CONSTRAINT questions_position_check CHECK (("position" > 0)),
    CONSTRAINT questions_text_check CHECK ((length(btrim(text)) > 0))
);


--
-- Name: questions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.questions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: questions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.questions_id_seq OWNED BY public.questions.id;


--
-- Name: quiz_attempts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quiz_attempts (
    id bigint NOT NULL,
    quiz_id bigint NOT NULL,
    student_username public.citext NOT NULL,
    attempt_no integer NOT NULL,
    score numeric(5,2) NOT NULL,
    passed boolean NOT NULL,
    submitted_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT quiz_attempts_attempt_no_check CHECK ((attempt_no > 0)),
    CONSTRAINT quiz_attempts_score_check CHECK (((score >= (0)::numeric) AND (score <= (100)::numeric)))
);


--
-- Name: quiz_attempts_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.quiz_attempts_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: quiz_attempts_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.quiz_attempts_id_seq OWNED BY public.quiz_attempts.id;


--
-- Name: quizzes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.quizzes (
    id bigint NOT NULL,
    module_id bigint NOT NULL,
    title text NOT NULL,
    pass_score numeric(5,2) DEFAULT 70 NOT NULL,
    max_attempts integer DEFAULT 3 NOT NULL,
    created_by public.citext,
    CONSTRAINT quizzes_max_attempts_check CHECK ((max_attempts > 0)),
    CONSTRAINT quizzes_pass_score_check CHECK (((pass_score >= (0)::numeric) AND (pass_score <= (100)::numeric))),
    CONSTRAINT quizzes_title_check CHECK ((length(btrim(title)) > 0))
);


--
-- Name: quizzes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.quizzes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: quizzes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.quizzes_id_seq OWNED BY public.quizzes.id;


--
-- Name: role_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.role_permissions (
    role_id bigint NOT NULL,
    permission_id bigint NOT NULL
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id bigint NOT NULL,
    name text NOT NULL
);


--
-- Name: roles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.roles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: roles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.roles_id_seq OWNED BY public.roles.id;


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id bigint NOT NULL,
    username public.citext NOT NULL,
    token_hash bytea NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    revoked boolean DEFAULT false NOT NULL
);


--
-- Name: sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sessions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sessions_id_seq OWNED BY public.sessions.id;


--
-- Name: user_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.user_roles (
    user_id bigint NOT NULL,
    role_id bigint NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id bigint NOT NULL,
    username public.citext NOT NULL,
    email public.citext,
    password_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    failed_attempts integer DEFAULT 0 NOT NULL,
    locked_until timestamp with time zone,
    is_active boolean DEFAULT true NOT NULL,
    CONSTRAINT username_len CHECK (((char_length((username)::text) >= 3) AND (char_length((username)::text) <= 64)))
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: achievements id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.achievements ALTER COLUMN id SET DEFAULT nextval('public.achievements_id_seq'::regclass);


--
-- Name: answer_options id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.answer_options ALTER COLUMN id SET DEFAULT nextval('public.answer_options_id_seq'::regclass);


--
-- Name: audit_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log ALTER COLUMN id SET DEFAULT nextval('public.audit_log_id_seq'::regclass);


--
-- Name: certificates id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificates ALTER COLUMN id SET DEFAULT nextval('public.certificates_id_seq'::regclass);


--
-- Name: comments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments ALTER COLUMN id SET DEFAULT nextval('public.comments_id_seq'::regclass);


--
-- Name: courses id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses ALTER COLUMN id SET DEFAULT nextval('public.courses_id_seq'::regclass);


--
-- Name: enrollments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments ALTER COLUMN id SET DEFAULT nextval('public.enrollments_id_seq'::regclass);


--
-- Name: materials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.materials ALTER COLUMN id SET DEFAULT nextval('public.materials_id_seq'::regclass);


--
-- Name: modules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modules ALTER COLUMN id SET DEFAULT nextval('public.modules_id_seq'::regclass);


--
-- Name: payments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments ALTER COLUMN id SET DEFAULT nextval('public.payments_id_seq'::regclass);


--
-- Name: permissions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions ALTER COLUMN id SET DEFAULT nextval('public.permissions_id_seq'::regclass);


--
-- Name: questions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questions ALTER COLUMN id SET DEFAULT nextval('public.questions_id_seq'::regclass);


--
-- Name: quiz_attempts id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quiz_attempts ALTER COLUMN id SET DEFAULT nextval('public.quiz_attempts_id_seq'::regclass);


--
-- Name: quizzes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quizzes ALTER COLUMN id SET DEFAULT nextval('public.quizzes_id_seq'::regclass);


--
-- Name: roles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles ALTER COLUMN id SET DEFAULT nextval('public.roles_id_seq'::regclass);


--
-- Name: sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions ALTER COLUMN id SET DEFAULT nextval('public.sessions_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Data for Name: achievements; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.achievements (id, student_username, course_id, title, details, created_at) FROM stdin;
\.


--
-- Data for Name: answer_options; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.answer_options (id, question_id, text, is_correct, "position") FROM stdin;
\.


--
-- Data for Name: attempt_answers; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.attempt_answers (attempt_id, quiz_id, question_id, option_id) FROM stdin;
\.


--
-- Data for Name: audit_log; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.audit_log (id, "timestamp", event_type, action, result, username, resource, details, prev_hash, entry_hash) FROM stdin;
1	2026-10-30 06:08:15.671754+00	AUTHENTICATION	REGISTER	SUCCESS	admin	users	User registered	\\x0000000000000000000000000000000000000000000000000000000000000000	\\xa070f3da4e88f54cad3644cbcc0d28946a7e07af045ffce3c12f21130f0cbac6
2	2026-10-30 06:10:49.384741+00	AUTHENTICATION	LOGIN	SUCCESS	admin	auth/password	\N	\\xa070f3da4e88f54cad3644cbcc0d28946a7e07af045ffce3c12f21130f0cbac6	\\xa11adbd36c85579d0ac9f973229fd966eca273534f9ad84bb548905072add667
3	2026-10-30 06:10:49.39816+00	ACCOUNTING	SESSION_CREATED	SUCCESS	admin	sessions	Session created via password	\\xa11adbd36c85579d0ac9f973229fd966eca273534f9ad84bb548905072add667	\\x5f4ec0faf6a5ea949f064576d62217faa54356de644bc771eb9c42478d2f814e
4	2026-10-30 06:10:49.476712+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	users.read	Permission granted	\\x5f4ec0faf6a5ea949f064576d62217faa54356de644bc771eb9c42478d2f814e	\\x8b383f26ce1e34df354f23ca329f6964a604f99d92d954447085c290fdee4ed0
5	2026-10-30 06:10:49.489825+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	roles.assign	Permission granted	\\x8b383f26ce1e34df354f23ca329f6964a604f99d92d954447085c290fdee4ed0	\\x3901a8ab668e1b2549fd5edb081b650a6d8c073838818c4dde3be4d24cdc8635
6	2026-10-30 06:12:57.098154+00	ACCOUNTING	LOGOUT	SUCCESS	admin	logout	Session revoked	\\x3901a8ab668e1b2549fd5edb081b650a6d8c073838818c4dde3be4d24cdc8635	\\x8f57b270f44b598d620c6af512b293fd3899a7833b640832114f49be2a860faa
7	2026-10-30 06:13:40.331231+00	AUTHENTICATION	REGISTER	SUCCESS	tutor	users	User registered	\\x8f57b270f44b598d620c6af512b293fd3899a7833b640832114f49be2a860faa	\\x1a2fdfd417425bb11d1a5f0b5b5f059a80bb43271ea9466247c1109854a9b005
8	2026-10-30 06:13:40.565805+00	AUTHENTICATION	LOGIN	SUCCESS	tutor	auth/password	\N	\\x1a2fdfd417425bb11d1a5f0b5b5f059a80bb43271ea9466247c1109854a9b005	\\xe97069c9b28ef128d878dc122d03b45db81d26c9a6406d48a55cb2020c49a8f3
9	2026-10-30 06:13:40.571361+00	ACCOUNTING	SESSION_CREATED	SUCCESS	tutor	sessions	Session created via password	\\xe97069c9b28ef128d878dc122d03b45db81d26c9a6406d48a55cb2020c49a8f3	\\xab010be94def4186f4539c6f20296cf53feeb34e0c570d394201b9f1400175e9
10	2026-10-30 06:14:06.29289+00	ACCOUNTING	LOGOUT	SUCCESS	tutor	logout	Session revoked	\\xab010be94def4186f4539c6f20296cf53feeb34e0c570d394201b9f1400175e9	\\x1c825ce9516a762cbc06ca9f6577af9735e0249f45a8f14d913cc99eef328c71
11	2026-10-30 06:14:24.521238+00	AUTHENTICATION	LOGIN	SUCCESS	admin	auth/password	\N	\\x1c825ce9516a762cbc06ca9f6577af9735e0249f45a8f14d913cc99eef328c71	\\x238f6f9c4c4cbdf7a668511c4eba95b3e01d5094509ad2eaa1dcc007f1680b92
12	2026-10-30 06:14:24.523104+00	ACCOUNTING	SESSION_CREATED	SUCCESS	admin	sessions	Session created via password	\\x238f6f9c4c4cbdf7a668511c4eba95b3e01d5094509ad2eaa1dcc007f1680b92	\\x2267e6d4e4d7d8e9b6ef112c8b782305f3b84b90e669e8999bb3e9f8c4f39673
13	2026-10-30 06:14:24.536635+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	users.read	Permission granted	\\x2267e6d4e4d7d8e9b6ef112c8b782305f3b84b90e669e8999bb3e9f8c4f39673	\\xb1ea682d67aba024bbd8c28a07452d0e1acae882ae4950788f74d129ed2c228d
14	2026-10-30 06:14:24.542369+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	roles.assign	Permission granted	\\xb1ea682d67aba024bbd8c28a07452d0e1acae882ae4950788f74d129ed2c228d	\\xc1344fe788b303af1b2b97e7855be8fe1be4d4c0630f1e54b0c2a835b977699a
15	2026-10-30 06:14:30.73778+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	roles.assign	Permission granted	\\xc1344fe788b303af1b2b97e7855be8fe1be4d4c0630f1e54b0c2a835b977699a	\\xd5402e2b9d3238b03bcd26c51120d7f7992ba16c3e53401a27ec05ed611f3e6e
16	2026-10-30 06:14:30.7489+00	ADMIN	ROLE_ASSIGN	SUCCESS	admin	user_roles	tutor -> tutor	\\xd5402e2b9d3238b03bcd26c51120d7f7992ba16c3e53401a27ec05ed611f3e6e	\\x61c024ddfae0512ad438f3d7bd940e2f339b0c47591b6dee8cc7693672b8922c
17	2026-10-30 06:14:30.761519+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	users.read	Permission granted	\\x61c024ddfae0512ad438f3d7bd940e2f339b0c47591b6dee8cc7693672b8922c	\\x2328301923944e42e1924cbb0b5be5d1885bb18953a3501e318937da0583b439
18	2026-10-30 06:14:30.768534+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	roles.assign	Permission granted	\\x2328301923944e42e1924cbb0b5be5d1885bb18953a3501e318937da0583b439	\\x51555fbf77f88742fd7fd29f771c350b980de40e1511c689dd3a41572c77339f
19	2026-10-30 06:15:00.310088+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	roles.assign	Permission granted	\\x51555fbf77f88742fd7fd29f771c350b980de40e1511c689dd3a41572c77339f	\\x2445832f3e0e525505134e745937ac8c49a423f99394ac6d3f37ff6113d85420
20	2026-10-30 06:15:00.321704+00	ADMIN	ROLE_REVOKE	SUCCESS	admin	user_roles	tutor <- tutor	\\x2445832f3e0e525505134e745937ac8c49a423f99394ac6d3f37ff6113d85420	\\x392d6891ed764960db13c109ddf5dfaf621dcc12323bd1b48e89fcfb8c9636a9
21	2026-10-30 06:15:00.334092+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	users.read	Permission granted	\\x392d6891ed764960db13c109ddf5dfaf621dcc12323bd1b48e89fcfb8c9636a9	\\xe28f78a0fb58376f89792d5f54493cbc29becb1cdd7629c0495daa5df0abd089
22	2026-10-30 06:15:00.338294+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	roles.assign	Permission granted	\\xe28f78a0fb58376f89792d5f54493cbc29becb1cdd7629c0495daa5df0abd089	\\x5987aeb2c8cf27e754f33f7cec7cef5e219bf2161f9b4a53b2361412f5c6eaba
23	2026-10-30 06:15:06.180226+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	roles.assign	Permission granted	\\x5987aeb2c8cf27e754f33f7cec7cef5e219bf2161f9b4a53b2361412f5c6eaba	\\xf8d9b2f0dac9577956802ee35b9eefe13a7f3fbd9254318a0e8ae7aa9b989a9d
24	2026-10-30 06:15:06.189358+00	ADMIN	ROLE_ASSIGN	SUCCESS	admin	user_roles	tutor -> tutor	\\xf8d9b2f0dac9577956802ee35b9eefe13a7f3fbd9254318a0e8ae7aa9b989a9d	\\x1d0cf25540caf4baed5403deedb67ad148577caddb7d681bc3b61371cb96c8c2
25	2026-10-30 06:15:06.198879+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	users.read	Permission granted	\\x1d0cf25540caf4baed5403deedb67ad148577caddb7d681bc3b61371cb96c8c2	\\x14ec34bcf9f1ffb47aadc54f6e7d10303fe8569c43da21767bee8ef4864b815d
26	2026-10-30 06:15:06.202616+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	roles.assign	Permission granted	\\x14ec34bcf9f1ffb47aadc54f6e7d10303fe8569c43da21767bee8ef4864b815d	\\xebe219d555c51cafd0802cc9b660db52545312c317586a8e1a6e8a0ad463d8d3
27	2026-10-30 06:15:19.936583+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	audit.read	Permission granted	\\xebe219d555c51cafd0802cc9b660db52545312c317586a8e1a6e8a0ad463d8d3	\\x9cf33512a838a6c220b4474f2fb5808ea644316f8e5c1eefd9522b934b6ce70b
28	2026-10-30 06:16:02.141056+00	ACCOUNTING	LOGOUT	SUCCESS	admin	logout	Session revoked	\\x9cf33512a838a6c220b4474f2fb5808ea644316f8e5c1eefd9522b934b6ce70b	\\x6b17d46595b0dca989a16278b3a71fc122f0ea513ca61c54016922fee4679558
29	2026-10-30 06:16:07.667301+00	AUTHENTICATION	LOGIN	FAILURE	tutor	auth/password	Invalid password	\\x6b17d46595b0dca989a16278b3a71fc122f0ea513ca61c54016922fee4679558	\\xa8263eac58b3b45814feadee73ae06e19fc68747e00c3f6186e0b6396b71af50
30	2026-10-30 06:16:16.490653+00	AUTHENTICATION	LOGIN	SUCCESS	admin	auth/password	\N	\\xa8263eac58b3b45814feadee73ae06e19fc68747e00c3f6186e0b6396b71af50	\\x40a47d10f8f684a8d0c557f5030d7f7c3a725065f9082aaac36f501adb8c6d6c
31	2026-10-30 06:16:16.493782+00	ACCOUNTING	SESSION_CREATED	SUCCESS	admin	sessions	Session created via password	\\x40a47d10f8f684a8d0c557f5030d7f7c3a725065f9082aaac36f501adb8c6d6c	\\x03f204b4cb67478421b3cab0462bec1c3a8bef9a3380a9eadd47f84e4802589f
32	2026-10-30 06:16:16.503399+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	users.read	Permission granted	\\x03f204b4cb67478421b3cab0462bec1c3a8bef9a3380a9eadd47f84e4802589f	\\x0b183b137722bd5de18da418bdee91140ed7141f439a240993789d57fafc94c5
33	2026-10-30 06:16:16.508097+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	roles.assign	Permission granted	\\x0b183b137722bd5de18da418bdee91140ed7141f439a240993789d57fafc94c5	\\xa49ed4ed8563ca948c1e557f7fb8b5a2ca8045057261cc9dc245623c425b9120
34	2026-10-30 06:16:18.75777+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	audit.read	Permission granted	\\xa49ed4ed8563ca948c1e557f7fb8b5a2ca8045057261cc9dc245623c425b9120	\\x37b78e580426144947b28f449f535cc1405021433be78248323f92acef58589c
35	2026-10-31 06:31:16.984938+00	AUTHENTICATION	LOGIN	SUCCESS	admin	auth/password	\N	\\x37b78e580426144947b28f449f535cc1405021433be78248323f92acef58589c	\\x38128f0cb8b14306c7b8fbfc89dfc27b83d0f9e30ef2078043a9139461c1022f
36	2026-10-31 06:31:16.995967+00	ACCOUNTING	SESSION_CREATED	SUCCESS	admin	sessions	Session created via password	\\x38128f0cb8b14306c7b8fbfc89dfc27b83d0f9e30ef2078043a9139461c1022f	\\xb8431558672bc26a595ee7b6427afb676f8a2f81d47ee3572ddcc3e50afd2272
37	2026-10-31 06:31:17.026268+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	users.read	Permission granted	\\xb8431558672bc26a595ee7b6427afb676f8a2f81d47ee3572ddcc3e50afd2272	\\xcac415a73aebd9ff3ba227fc4d14734d945567a12d8268573cdcd936d10f1322
38	2026-10-31 06:31:17.031237+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	roles.assign	Permission granted	\\xcac415a73aebd9ff3ba227fc4d14734d945567a12d8268573cdcd936d10f1322	\\x894373b024fdccd20980e56cd3e5612a187b9bbc4b41e82d5f0a992cade091d1
39	2026-10-31 06:32:26.179713+00	AUTHENTICATION	PASSWORD_CHANGE	SUCCESS	admin	users	\N	\\x894373b024fdccd20980e56cd3e5612a187b9bbc4b41e82d5f0a992cade091d1	\\x88810da9716dc0b2a843272174d1baf765bf8dabbb4760228c26a163edccf475
40	2026-10-31 06:32:30.715004+00	ACCOUNTING	LOGOUT	SUCCESS	admin	logout	Session revoked	\\x88810da9716dc0b2a843272174d1baf765bf8dabbb4760228c26a163edccf475	\\xac2ca7a45abde2d2b0ecd5c913c000c819eced037a6e9643a01dea2c149f2095
41	2026-10-31 06:32:46.65932+00	AUTHENTICATION	LOGIN	SUCCESS	admin	auth/password	\N	\\xac2ca7a45abde2d2b0ecd5c913c000c819eced037a6e9643a01dea2c149f2095	\\xe5d128f01f8c29e17436e2c32d34f8f89702ad0fe005b8e19de3618f54860087
42	2026-10-31 06:32:46.660745+00	ACCOUNTING	SESSION_CREATED	SUCCESS	admin	sessions	Session created via password	\\xe5d128f01f8c29e17436e2c32d34f8f89702ad0fe005b8e19de3618f54860087	\\xcf909719788e2697999301f06b51f12435ce9d5aee030523c55122dbfd69db6a
43	2026-10-31 06:32:46.665901+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	users.read	Permission granted	\\xcf909719788e2697999301f06b51f12435ce9d5aee030523c55122dbfd69db6a	\\xfb254d4ab830f50f75a1c546b85cfb991692612db2c0764f210c7ffb2c853c29
44	2026-10-31 06:32:46.668091+00	AUTHORIZATION	ACCESS_GRANTED	SUCCESS	admin	roles.assign	Permission granted	\\xfb254d4ab830f50f75a1c546b85cfb991692612db2c0764f210c7ffb2c853c29	\\xbbf89d447130e61197024ee601bd8b9517772d8e69ea0b46610b364f7d82dc62
45	2026-10-31 06:33:01.946567+00	ACCOUNTING	LOGOUT	SUCCESS	admin	logout	Session revoked	\\xbbf89d447130e61197024ee601bd8b9517772d8e69ea0b46610b364f7d82dc62	\\x71552049590f827f99c3f5f41a8e81f6ed951c94d10ef81a607821d70086405d
\.


--
-- Data for Name: certificates; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.certificates (id, certificate_no, student_username, course_id, issued_at) FROM stdin;
\.


--
-- Data for Name: comments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.comments (id, student_username, author_username, text, created_at) FROM stdin;
\.


--
-- Data for Name: course_tutors; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.course_tutors (course_id, tutor_username, assigned_at) FROM stdin;
\.


--
-- Data for Name: courses; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.courses (id, name, slug, description, cover_url, is_published, price_amount, currency, created_at) FROM stdin;
1	Mathematics 101	\N		\N	t	0.00	USD	2026-10-30 06:08:14.8518+00
2	Intro to Programming	\N		\N	t	0.00	USD	2026-10-30 06:08:14.8518+00
\.


--
-- Data for Name: enrollments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.enrollments (id, student_username, course_id, status, decided_by, requested_at, decided_at) FROM stdin;
\.


--
-- Data for Name: material_progress; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.material_progress (student_username, material_id, completed_at) FROM stdin;
\.


--
-- Data for Name: materials; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.materials (id, module_id, kind, title, body, resource_url, "position", created_by, created_at) FROM stdin;
\.


--
-- Data for Name: modules; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.modules (id, course_id, title, "position") FROM stdin;
\.


--
-- Data for Name: payments; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.payments (id, student_username, course_id, amount, currency, status, provider, provider_ref, created_at, paid_at) FROM stdin;
\.


--
-- Data for Name: permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.permissions (id, name) FROM stdin;
1	profile.read
2	profile.write
3	users.read
4	users.delete
5	audit.read
6	achievements.read
7	comments.write
8	enrollment.approve
9	roles.assign
10	content.manage
11	results.read
12	payments.read
13	payments.manage
\.


--
-- Data for Name: questions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.questions (id, quiz_id, text, kind, "position") FROM stdin;
\.


--
-- Data for Name: quiz_attempts; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.quiz_attempts (id, quiz_id, student_username, attempt_no, score, passed, submitted_at) FROM stdin;
\.


--
-- Data for Name: quizzes; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.quizzes (id, module_id, title, pass_score, max_attempts, created_by) FROM stdin;
\.


--
-- Data for Name: role_permissions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.role_permissions (role_id, permission_id) FROM stdin;
1	1
1	2
2	1
2	2
2	3
2	4
2	5
2	9
2	10
2	11
3	1
3	2
3	6
3	7
3	8
3	11
2	12
2	13
\.


--
-- Data for Name: roles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.roles (id, name) FROM stdin;
1	user
2	admin
3	tutor
\.


--
-- Data for Name: sessions; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.sessions (id, username, token_hash, created_at, expires_at, revoked) FROM stdin;
1	admin	\\x4008aacf983cabeb4941b0c4f3bea96796bba1ea98a3e0e89285e07506263793	2026-10-30 06:10:49.39138+00	2026-10-30 06:40:49.389615+00	t
2	tutor	\\x22d5463f9df4f9de069dc744d0b25a7db2162fe4de8412c9cf23bb895970a978	2026-10-30 06:13:40.56813+00	2026-10-30 06:43:40.567674+00	t
3	admin	\\x0852d6b2b430d101fee88d05dcae4ba86b686bc45e05aa81b0cecb6891ef984b	2026-10-30 06:14:24.52243+00	2026-10-30 06:44:24.522306+00	t
4	admin	\\x75a8170baa75177a545f73ec52eb2852489da445bebb1b14f077bac0c807866f	2026-10-30 06:16:16.492318+00	2026-10-30 06:46:16.492011+00	f
5	admin	\\x6b3694bdd7c9dddad8818367ae3e1a3b7dd5dd2c37bf62e526fa44e4b5a74aee	2026-10-31 06:31:16.99393+00	2026-10-31 07:01:16.993256+00	t
6	admin	\\x726c6aa2827b7881f32da11ba268d0b61471287b2dcaf5286a0c3c0db5580c91	2026-10-31 06:32:46.660184+00	2026-10-31 07:02:46.660061+00	t
\.


--
-- Data for Name: user_roles; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.user_roles (user_id, role_id) FROM stdin;
1	1
1	2
2	1
2	3
\.


--
-- Data for Name: users; Type: TABLE DATA; Schema: public; Owner: -
--

COPY public.users (id, username, email, password_hash, created_at, failed_attempts, locked_until, is_active) FROM stdin;
2	tutor	tutor@mail.com	argon2id$v=19$m=65536,t=3,p=4$8w9M99r0iewyCRo+bGuqjQ==$wCH251hvH03XCqXSXSkJ4EZduJHFlji/8mv1tnmdYEg=	2026-10-30 06:13:40.318161+00	1	\N	t
1	admin	\N	argon2id$v=19$m=65536,t=3,p=4$Sf0qQKxXkpaK8Uwm1XEHdw==$7qq4K0kHKeMc2TnOrqN+M/Zdmwpwn/A2wqUwfUY2aGA=	2026-10-30 06:08:15.653456+00	0	\N	t
\.


--
-- Name: achievements_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.achievements_id_seq', 1, false);


--
-- Name: answer_options_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.answer_options_id_seq', 1, false);


--
-- Name: audit_log_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.audit_log_id_seq', 45, true);


--
-- Name: certificate_no_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.certificate_no_seq', 1, false);


--
-- Name: certificates_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.certificates_id_seq', 1, false);


--
-- Name: comments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.comments_id_seq', 1, false);


--
-- Name: courses_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.courses_id_seq', 4, true);


--
-- Name: enrollments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.enrollments_id_seq', 1, false);


--
-- Name: materials_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.materials_id_seq', 1, false);


--
-- Name: modules_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.modules_id_seq', 1, false);


--
-- Name: payments_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.payments_id_seq', 1, false);


--
-- Name: permissions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.permissions_id_seq', 26, true);


--
-- Name: questions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.questions_id_seq', 1, false);


--
-- Name: quiz_attempts_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.quiz_attempts_id_seq', 1, false);


--
-- Name: quizzes_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.quizzes_id_seq', 1, false);


--
-- Name: roles_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.roles_id_seq', 6, true);


--
-- Name: sessions_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.sessions_id_seq', 6, true);


--
-- Name: users_id_seq; Type: SEQUENCE SET; Schema: public; Owner: -
--

SELECT pg_catalog.setval('public.users_id_seq', 2, true);


--
-- Name: achievements achievements_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.achievements
    ADD CONSTRAINT achievements_pkey PRIMARY KEY (id);


--
-- Name: answer_options answer_options_id_question_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.answer_options
    ADD CONSTRAINT answer_options_id_question_id_key UNIQUE (id, question_id);


--
-- Name: answer_options answer_options_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.answer_options
    ADD CONSTRAINT answer_options_pkey PRIMARY KEY (id);


--
-- Name: answer_options answer_options_question_id_position_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.answer_options
    ADD CONSTRAINT answer_options_question_id_position_key UNIQUE (question_id, "position");


--
-- Name: attempt_answers attempt_answers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attempt_answers
    ADD CONSTRAINT attempt_answers_pkey PRIMARY KEY (attempt_id, question_id, option_id);


--
-- Name: audit_log audit_log_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.audit_log
    ADD CONSTRAINT audit_log_pkey PRIMARY KEY (id);


--
-- Name: certificates certificates_certificate_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificates
    ADD CONSTRAINT certificates_certificate_no_key UNIQUE (certificate_no);


--
-- Name: certificates certificates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificates
    ADD CONSTRAINT certificates_pkey PRIMARY KEY (id);


--
-- Name: certificates certificates_student_username_course_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificates
    ADD CONSTRAINT certificates_student_username_course_id_key UNIQUE (student_username, course_id);


--
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (id);


--
-- Name: course_tutors course_tutors_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_tutors
    ADD CONSTRAINT course_tutors_pkey PRIMARY KEY (course_id, tutor_username);


--
-- Name: courses courses_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_name_key UNIQUE (name);


--
-- Name: courses courses_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.courses
    ADD CONSTRAINT courses_pkey PRIMARY KEY (id);


--
-- Name: enrollments enrollments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_pkey PRIMARY KEY (id);


--
-- Name: enrollments enrollments_student_username_course_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_student_username_course_id_key UNIQUE (student_username, course_id);


--
-- Name: material_progress material_progress_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.material_progress
    ADD CONSTRAINT material_progress_pkey PRIMARY KEY (student_username, material_id);


--
-- Name: materials materials_module_id_position_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.materials
    ADD CONSTRAINT materials_module_id_position_key UNIQUE (module_id, "position");


--
-- Name: materials materials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.materials
    ADD CONSTRAINT materials_pkey PRIMARY KEY (id);


--
-- Name: modules modules_course_id_position_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modules
    ADD CONSTRAINT modules_course_id_position_key UNIQUE (course_id, "position");


--
-- Name: modules modules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modules
    ADD CONSTRAINT modules_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: permissions permissions_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_name_key UNIQUE (name);


--
-- Name: permissions permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.permissions
    ADD CONSTRAINT permissions_pkey PRIMARY KEY (id);


--
-- Name: questions questions_id_quiz_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questions
    ADD CONSTRAINT questions_id_quiz_id_key UNIQUE (id, quiz_id);


--
-- Name: questions questions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questions
    ADD CONSTRAINT questions_pkey PRIMARY KEY (id);


--
-- Name: questions questions_quiz_id_position_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questions
    ADD CONSTRAINT questions_quiz_id_position_key UNIQUE (quiz_id, "position");


--
-- Name: quiz_attempts quiz_attempts_id_quiz_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quiz_attempts
    ADD CONSTRAINT quiz_attempts_id_quiz_id_key UNIQUE (id, quiz_id);


--
-- Name: quiz_attempts quiz_attempts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quiz_attempts
    ADD CONSTRAINT quiz_attempts_pkey PRIMARY KEY (id);


--
-- Name: quiz_attempts quiz_attempts_quiz_id_student_username_attempt_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quiz_attempts
    ADD CONSTRAINT quiz_attempts_quiz_id_student_username_attempt_no_key UNIQUE (quiz_id, student_username, attempt_no);


--
-- Name: quizzes quizzes_module_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quizzes
    ADD CONSTRAINT quizzes_module_id_key UNIQUE (module_id);


--
-- Name: quizzes quizzes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quizzes
    ADD CONSTRAINT quizzes_pkey PRIMARY KEY (id);


--
-- Name: role_permissions role_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_pkey PRIMARY KEY (role_id, permission_id);


--
-- Name: roles roles_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_name_key UNIQUE (name);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: sessions sessions_token_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_token_hash_key UNIQUE (token_hash);


--
-- Name: user_roles user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_pkey PRIMARY KEY (user_id, role_id);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: idx_achievements_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_achievements_student ON public.achievements USING btree (student_username);


--
-- Name: idx_audit_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_audit_username ON public.audit_log USING btree (username);


--
-- Name: idx_comments_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_comments_student ON public.comments USING btree (student_username);


--
-- Name: idx_enrollments_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_enrollments_status ON public.enrollments USING btree (status);


--
-- Name: idx_enrollments_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_enrollments_student ON public.enrollments USING btree (student_username);


--
-- Name: idx_payments_course; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_course ON public.payments USING btree (course_id);


--
-- Name: idx_payments_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_payments_student ON public.payments USING btree (student_username);


--
-- Name: idx_quiz_attempts_student; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_quiz_attempts_student ON public.quiz_attempts USING btree (student_username, submitted_at DESC);


--
-- Name: idx_sessions_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_sessions_username ON public.sessions USING btree (username);


--
-- Name: uq_courses_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_courses_slug ON public.courses USING btree (slug) WHERE (slug IS NOT NULL);


--
-- Name: uq_payments_one_paid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_payments_one_paid ON public.payments USING btree (student_username, course_id) WHERE (status = 'Paid'::text);


--
-- Name: uq_payments_provider_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX uq_payments_provider_ref ON public.payments USING btree (provider, provider_ref) WHERE (provider_ref IS NOT NULL);


--
-- Name: certificates certificates_eligibility; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER certificates_eligibility BEFORE INSERT ON public.certificates FOR EACH ROW EXECUTE FUNCTION public.trg_certificate_eligibility();


--
-- Name: material_progress material_progress_require_access; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER material_progress_require_access BEFORE INSERT ON public.material_progress FOR EACH ROW EXECUTE FUNCTION public.trg_require_course_access();


--
-- Name: quiz_attempts quiz_attempts_require_access; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER quiz_attempts_require_access BEFORE INSERT ON public.quiz_attempts FOR EACH ROW EXECUTE FUNCTION public.trg_require_course_access();


--
-- Name: achievements achievements_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.achievements
    ADD CONSTRAINT achievements_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: achievements achievements_student_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.achievements
    ADD CONSTRAINT achievements_student_username_fkey FOREIGN KEY (student_username) REFERENCES public.users(username) ON DELETE CASCADE;


--
-- Name: answer_options answer_options_question_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.answer_options
    ADD CONSTRAINT answer_options_question_id_fkey FOREIGN KEY (question_id) REFERENCES public.questions(id) ON DELETE CASCADE;


--
-- Name: attempt_answers attempt_answers_attempt_id_quiz_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attempt_answers
    ADD CONSTRAINT attempt_answers_attempt_id_quiz_id_fkey FOREIGN KEY (attempt_id, quiz_id) REFERENCES public.quiz_attempts(id, quiz_id) ON DELETE CASCADE;


--
-- Name: attempt_answers attempt_answers_option_id_question_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attempt_answers
    ADD CONSTRAINT attempt_answers_option_id_question_id_fkey FOREIGN KEY (option_id, question_id) REFERENCES public.answer_options(id, question_id) ON DELETE CASCADE;


--
-- Name: attempt_answers attempt_answers_question_id_quiz_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attempt_answers
    ADD CONSTRAINT attempt_answers_question_id_quiz_id_fkey FOREIGN KEY (question_id, quiz_id) REFERENCES public.questions(id, quiz_id) ON DELETE CASCADE;


--
-- Name: certificates certificates_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificates
    ADD CONSTRAINT certificates_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE RESTRICT;


--
-- Name: certificates certificates_student_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.certificates
    ADD CONSTRAINT certificates_student_username_fkey FOREIGN KEY (student_username) REFERENCES public.users(username) ON DELETE CASCADE;


--
-- Name: comments comments_author_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_author_username_fkey FOREIGN KEY (author_username) REFERENCES public.users(username) ON DELETE CASCADE;


--
-- Name: comments comments_student_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_student_username_fkey FOREIGN KEY (student_username) REFERENCES public.users(username) ON DELETE CASCADE;


--
-- Name: course_tutors course_tutors_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_tutors
    ADD CONSTRAINT course_tutors_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: course_tutors course_tutors_tutor_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.course_tutors
    ADD CONSTRAINT course_tutors_tutor_username_fkey FOREIGN KEY (tutor_username) REFERENCES public.users(username) ON DELETE CASCADE;


--
-- Name: enrollments enrollments_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: enrollments enrollments_student_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.enrollments
    ADD CONSTRAINT enrollments_student_username_fkey FOREIGN KEY (student_username) REFERENCES public.users(username) ON DELETE CASCADE;


--
-- Name: material_progress material_progress_material_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.material_progress
    ADD CONSTRAINT material_progress_material_id_fkey FOREIGN KEY (material_id) REFERENCES public.materials(id) ON DELETE CASCADE;


--
-- Name: material_progress material_progress_student_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.material_progress
    ADD CONSTRAINT material_progress_student_username_fkey FOREIGN KEY (student_username) REFERENCES public.users(username) ON DELETE CASCADE;


--
-- Name: materials materials_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.materials
    ADD CONSTRAINT materials_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(username) ON DELETE SET NULL;


--
-- Name: materials materials_module_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.materials
    ADD CONSTRAINT materials_module_id_fkey FOREIGN KEY (module_id) REFERENCES public.modules(id) ON DELETE CASCADE;


--
-- Name: modules modules_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.modules
    ADD CONSTRAINT modules_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE CASCADE;


--
-- Name: payments payments_course_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_course_id_fkey FOREIGN KEY (course_id) REFERENCES public.courses(id) ON DELETE RESTRICT;


--
-- Name: payments payments_student_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_student_username_fkey FOREIGN KEY (student_username) REFERENCES public.users(username) ON DELETE RESTRICT;


--
-- Name: questions questions_quiz_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.questions
    ADD CONSTRAINT questions_quiz_id_fkey FOREIGN KEY (quiz_id) REFERENCES public.quizzes(id) ON DELETE CASCADE;


--
-- Name: quiz_attempts quiz_attempts_quiz_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quiz_attempts
    ADD CONSTRAINT quiz_attempts_quiz_id_fkey FOREIGN KEY (quiz_id) REFERENCES public.quizzes(id) ON DELETE CASCADE;


--
-- Name: quiz_attempts quiz_attempts_student_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quiz_attempts
    ADD CONSTRAINT quiz_attempts_student_username_fkey FOREIGN KEY (student_username) REFERENCES public.users(username) ON DELETE CASCADE;


--
-- Name: quizzes quizzes_created_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quizzes
    ADD CONSTRAINT quizzes_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.users(username) ON DELETE SET NULL;


--
-- Name: quizzes quizzes_module_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.quizzes
    ADD CONSTRAINT quizzes_module_id_fkey FOREIGN KEY (module_id) REFERENCES public.modules(id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_permission_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_permission_id_fkey FOREIGN KEY (permission_id) REFERENCES public.permissions(id) ON DELETE CASCADE;


--
-- Name: role_permissions role_permissions_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.role_permissions
    ADD CONSTRAINT role_permissions_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: sessions sessions_username_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_username_fkey FOREIGN KEY (username) REFERENCES public.users(username) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_role_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_role_id_fkey FOREIGN KEY (role_id) REFERENCES public.roles(id) ON DELETE CASCADE;


--
-- Name: user_roles user_roles_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.user_roles
    ADD CONSTRAINT user_roles_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict gbqM4nDvOBtGIxeaSho1ZjgVQzRatwEcLMObZ4rVhMKE5LilNq1PwSPctSIkvvp

