"""
Permission tests for the Mukhtabarat database.

Plays every role (patient, clerk, runner, lab owner, super admin, anonymous)
and checks that each can do what it should and nothing more.

Run against a throwaway Postgres that has the migrations applied:
    DATABASE_URL=postgresql://postgres@localhost:54329/t python3 permissions_test.py
"""
import json
import os
import sys
import uuid

import psycopg2

conn = psycopg2.connect(os.environ.get("DATABASE_URL", "host=/tmp port=54329 user=postgres dbname=t"))
conn.autocommit = True
failures = []
passed = 0


def as_user(uid, role="authenticated"):
    """Return a cursor acting as the given user (None = anonymous)."""
    cur = conn.cursor()
    cur.execute("reset role")
    claims = {"role": role}
    if uid:
        claims["sub"] = str(uid)
    cur.execute("select set_config('request.jwt.claims', %s, false)", (json.dumps(claims),))
    cur.execute(f"set role {role}")
    return cur


def backend():
    return as_user(None, "service_role")


def check(name, cond):
    global passed
    if cond:
        passed += 1
    else:
        failures.append(name)
        print(f"  FAIL: {name}")


def allowed(name, uid, sql, args=(), role="authenticated"):
    cur = as_user(uid, role)
    try:
        cur.execute(sql, args)
        rows = cur.fetchall() if cur.description else None
        check(name, True)
        return rows
    except psycopg2.Error as e:
        check(f"{name}  (error: {e.pgerror.strip().splitlines()[0] if e.pgerror else e})", False)
        return None


def denied(name, uid, sql, args=(), role="authenticated"):
    """Must raise, or affect/return zero rows."""
    cur = as_user(uid, role)
    try:
        cur.execute(sql, args)
        rows = cur.fetchall() if cur.description else []
        ok = (not rows) and cur.rowcount in (0, -1)
        if rows and len(rows) == 1 and rows[0] == (None,):
            ok = True
        check(f"{name}  (should have been blocked, got {rows or cur.rowcount})" if not ok else name, ok)
    except psycopg2.Error:
        check(name, True)


def scalar(cur, sql, args=()):
    cur.execute(sql, args)
    return cur.fetchone()[0]


def new_user(name, phone=None):
    uid = uuid.uuid4()
    cur = as_user(None, "postgres") if False else conn.cursor()
    cur.execute("reset role")
    cur.execute("select set_config('request.jwt.claims', '', false)")
    cur.execute(
        "insert into auth.users (id, phone, raw_user_meta_data) values (%s, %s, %s)",
        (str(uid), phone, json.dumps({"full_name": name})),
    )
    return uid


# ---------------------------------------------------------------- setup
print("Setting up labs and accounts...")
SA = new_user("Super Admin")
c = conn.cursor()
c.execute("reset role")
c.execute("update public.profiles set role = 'super_admin' where id = %s", (str(SA),))

L1 = allowed("super admin creates lab 1", SA,
             "insert into labs (name_ar, name_en, area_en) values ('مختبر ١', 'Lab One', 'Mansour') returning id")[0][0]
L2 = allowed("super admin creates lab 2", SA,
             "insert into labs (name_ar, name_en) values ('مختبر ٢', 'Lab Two') returning id")[0][0]


def make_staff(inviter, lab, role, name):
    rows = allowed(f"{role} invite for {name}", inviter,
                   "select token from create_staff_invite(%s, %s)", (lab, role))
    token = rows[0][0]
    uid = new_user(name)
    backend().execute("select claim_staff_invite(%s, %s, %s)", (token, str(uid), name))
    return uid, token


A1, _ = make_staff(SA, L1, "lab_admin", "Owner One")
A2, _ = make_staff(SA, L2, "lab_admin", "Owner Two")
R1, _ = make_staff(A1, L1, "runner", "Runner One")
C1, used_token = make_staff(A1, L1, "clerk", "Clerk One")
C2, _ = make_staff(A2, L2, "clerk", "Clerk Two")
U1 = new_user("Patient One", "9647700000001")
U2 = new_user("Patient Two", "9647700000002")

check("roles assigned by invite",
      scalar(backend(), "select string_agg(role::text, ',' order by full_name) from profiles where id in (%s,%s,%s)",
             (str(A1), str(R1), str(C1))) == "clerk,lab_admin,runner")

P1 = allowed("lab owner adds package", A1,
             "insert into packages (lab_id, name_ar, name_en, price_iqd) values (%s, 'فحص', 'Checkup', 10000) returning id",
             (L1,))[0][0]
P2 = allowed("lab 2 owner adds package", A2,
             "insert into packages (lab_id, name_ar, name_en, price_iqd) values (%s, 'فحص ٢', 'Checkup 2', 20000) returning id",
             (L2,))[0][0]

# ---------------------------------------------------------------- browsing
print("Browsing and labs...")
check("anonymous visitor can browse labs",
      len(allowed("anon reads labs", None, "select id from labs", role="anon")) == 2)
denied("lab owner can't add packages to another lab", A1,
       "insert into packages (lab_id, name_ar, name_en, price_iqd) values (%s, 'x', 'x', 1)", (L2,))
allowed("lab owner edits own lab details", A1, "update labs set contact_phone = '0770' where id = %s", (L1,))
denied("lab owner can't change own commission", A1, "update labs set commission_rate = 0 where id = %s", (L1,))
denied("lab owner can't deactivate own lab", A1, "update labs set is_active = false where id = %s", (L1,))
denied("lab owner can't edit another lab", A1, "update labs set name_en = 'hacked' where id = %s returning id", (L2,))
denied("lab owner can't delete labs", A1, "delete from labs where id = %s returning id", (L1,))
denied("lab owner can't change platform commission", A1, "update app_settings set commission_rate = 0 returning 1")
allowed("super admin changes platform commission", SA, "update app_settings set commission_rate = 0.15")

# ---------------------------------------------------------------- booking
print("Booking...")
O1 = allowed("patient books", U1,
             "insert into orders (client_request_id, package_id, location_lat, location_lng, price_iqd, commission_rate, commission_iqd, package_name_ar, package_name_en, lab_id, patient_id) "
             "values (gen_random_uuid(), %s, 33.31, 44.36, 1, 0, 0, 'x', 'x', %s, %s) returning id, price_iqd, commission_iqd, patient_id, status",
             (P1, L2, str(U2)))
order1, price, comm, owner, status = O1[0]
check("price comes from the package, not the phone", price == 10000)
check("commission is 15%", comm == 1500)
check("can't book on someone else's behalf", str(owner) == str(U1))
check("new order is pending", status == "pending")

req_id = str(uuid.uuid4())
allowed("patient 2 books lab 2", U2,
        "insert into orders (client_request_id, package_id, location_lat, location_lng, price_iqd, commission_rate, commission_iqd, package_name_ar, package_name_en, lab_id, patient_id) "
        "values (%s, %s, 33.3, 44.3, 0,0,0,'','',%s,%s)", (req_id, P2, L2, str(U2)))
denied("retrying the same booking doesn't duplicate it", U2,
       "insert into orders (client_request_id, package_id, location_lat, location_lng, price_iqd, commission_rate, commission_iqd, package_name_ar, package_name_en, lab_id, patient_id) "
       "values (%s, %s, 33.3, 44.3, 0,0,0,'','',%s,%s)", (req_id, P2, L2, str(U2)))

check("patient sees own orders only",
      len(allowed("patient 1 lists orders", U1, "select id from orders")) == 1)
check("patient 2 can't see patient 1's order",
      not allowed("patient 2 looks", U2, "select id from orders where id = %s", (order1,)))
denied("patient can't edit order directly", U1, "update orders set price_iqd = 0 where id = %s returning id", (order1,))
denied("patient can't accept own order", U1, "select update_order_status(%s, 'accepted')", (order1,))
denied("patient can't make themselves staff", U1, "update profiles set role = 'clerk', lab_id = %s where id = %s", (L1, str(U1)))
allowed("patient can rename themselves", U1, "update profiles set full_name = 'Patient 1' where id = %s", (str(U1),))

# ---------------------------------------------------------------- lab side
print("Lab workflow...")
check("clerk sees lab's order", bool(allowed("clerk lists", C1, "select id from orders where id = %s", (order1,))))
check("clerk sees patient's name",
      bool(allowed("clerk reads patient", C1, "select full_name from profiles where id = %s", (str(U1),))))
check("other lab's clerk can't see the order",
      not allowed("clerk 2 lists", C2, "select id from orders where id = %s", (order1,)))
check("other lab's clerk can't see the patient",
      not allowed("clerk 2 reads patient", C2, "select full_name from profiles where id = %s", (str(U1),)))
check("phone numbers aren't visible to staff (not in profiles)",
      "phone" not in [d[0] for d in (lambda cur: (cur.execute("select * from profiles limit 0"), cur.description)[1])(as_user(C1))])
denied("staff can't read patient phone", C1, "select user_phone(%s)", (str(U1),))
denied("staff can't search all users", C1, "select * from admin_list_users(null)")
check("super admin can search users with phones",
      any(r[5] == "9647700000001" for r in allowed("super admin user search", SA, "select * from admin_list_users('Patient')")))

denied("other lab's clerk can't accept", C2, "select update_order_status(%s, 'accepted')", (order1,))
allowed("clerk accepts", C1, "select update_order_status(%s, 'accepted')", (order1,))
denied("can't dispatch without a runner", A1, "select update_order_status(%s, 'on_way')", (order1,))
denied("clerk can't dispatch", C1, "select update_order_status(%s, 'on_way')", (order1,))
denied("can't assign a clerk as runner", A1, "select assign_runner(%s, %s)", (order1, str(C1)))
allowed("clerk assigns runner", C1, "select assign_runner(%s, %s)", (order1, str(R1)))
denied("runner can't share location before leaving", R1, "select update_runner_location(%s, 33.3, 44.3)", (order1,))
allowed("runner sets off", R1, "select update_order_status(%s, 'on_way')", (order1,))
denied("patient can't cancel once runner is on the way", U1, "select update_order_status(%s, 'cancelled')", (order1,))
allowed("runner shares live location", R1, "select update_runner_location(%s, 33.312, 44.361)", (order1,))
denied("patient can't fake runner location", U1, "select update_runner_location(%s, 1, 1)", (order1,))
check("patient sees runner moving",
      bool(allowed("patient reads location", U1, "select lat from runner_locations where order_id = %s", (order1,))))
check("patient sees runner's name",
      bool(allowed("patient reads runner", U1, "select full_name from profiles where id = %s", (str(R1),))))
check("other patient can't see runner location",
      not allowed("patient 2 reads location", U2, "select lat from runner_locations where order_id = %s", (order1,)))
allowed("runner collects sample", R1, "select update_order_status(%s, 'sample_taken')", (order1,))
check("tracking stops after collection",
      scalar(backend(), "select count(*) from runner_locations where order_id = %s", (order1,)) == 0)

# ---------------------------------------------------------------- documents
print("Documents...")
path = f"{L1}/{U1}/{uuid.uuid4()}-result.pdf"
allowed("clerk uploads file", C1, "insert into storage.objects (bucket_id, name) values ('patient-documents', %s)", (path,))
doc = allowed("clerk records document", C1,
              "insert into patient_documents (patient_id, lab_id, order_id, file_name, mime_type, size_bytes, storage_path) "
              "values (%s, %s, %s, 'result.pdf', 'application/pdf', 1000, %s) returning id",
              (str(U1), L1, order1, path))[0][0]
other_path = f"{L2}/{U1}/{uuid.uuid4()}-x.pdf"
denied("other lab can't upload for a patient who never booked with them", C2,
       "insert into storage.objects (bucket_id, name) values ('patient-documents', %s)", (other_path,))
denied("staff can't upload into another lab's folder", C2,
       "insert into storage.objects (bucket_id, name) values ('patient-documents', %s)", (f"{L1}/{U1}/x.pdf",))
check("patient sees own result",
      bool(allowed("patient lists docs", U1, "select id from patient_documents where id = %s", (doc,))))
check("patient can open own file",
      bool(allowed("patient opens file", U1, "select id from storage.objects where name = %s", (path,))))
check("other patient can't open file",
      not allowed("patient 2 opens file", U2, "select id from storage.objects where name = %s", (path,)))
check("other lab can't see documents",
      not allowed("clerk 2 lists docs", C2, "select id from patient_documents where id = %s", (doc,)))
allowed("clerk completes order", C1, "select update_order_status(%s, 'completed')", (order1,))
denied("patient can't delete documents", U1, "select delete_patient_document(%s)", (doc,))
allowed("clerk deletes document", C1, "select delete_patient_document(%s)", (doc,))
check("deleted document hidden from patient",
      not allowed("patient lists docs again", U1, "select id from patient_documents where id = %s", (doc,)))
check("deleted file can't be opened",
      not allowed("patient opens deleted file", U1, "select id from storage.objects where name = %s", (path,)))
check("super admin can still see deleted record",
      bool(allowed("super admin sees deleted doc", SA, "select id from patient_documents where id = %s", (doc,))))

# ---------------------------------------------------------------- invites
print("Invites...")
denied("used invite link is burned", None, "select * from peek_staff_invite(%s)", (used_token,), role="anon")
uid_x = new_user("Late Person")
denied("used invite can't make a second account", None,
       "select claim_staff_invite(%s, %s, 'x')", (used_token, str(uid_x)), role="service_role")
tok = allowed("owner makes invite", A1, "select token from create_staff_invite(%s, 'runner')", (L1,))[0][0]
check("fresh invite is valid", bool(allowed("anon peeks invite", None, "select role from peek_staff_invite(%s)", (tok,), role="anon")))
c.execute("reset role")
c.execute("update staff_invites set expires_at = now() - interval '1 second' where token_hash = hash_invite_token(%s)", (tok,))
denied("invite expires after an hour", None, "select claim_staff_invite(%s, %s, 'x')", (tok, str(uid_x)), role="service_role")
denied("runner can't create invites", R1, "select create_staff_invite(%s, 'clerk')", (L1,))
denied("owner can't invite another owner", A1, "select create_staff_invite(%s, 'lab_admin')", (L1,))
denied("owner can't invite into another lab", A1, "select create_staff_invite(%s, 'clerk')", (L2,))
denied("patient can't burn invites from the app", U1, "select claim_staff_invite(%s, %s, 'x')", (tok, str(U1)))
denied("anonymous can't create invites", None, "select create_staff_invite(%s, 'clerk')", (L1,), role="anon")
denied("anon can't see invites table", None, "select * from staff_invites", role="anon")

# ---------------------------------------------------------------- staff management
print("Staff management...")
allowed("owner switches runner to clerk", A1, "select set_employee_role(%s, 'clerk')", (str(R1),))
allowed("owner switches back", A1, "select set_employee_role(%s, 'runner')", (str(R1),))
denied("owner can't promote to owner", A1, "select set_employee_role(%s, 'lab_admin')", (str(R1),))
denied("nobody can grant super admin from the app", SA, "select set_employee_role(%s, 'super_admin')", (str(R1),))
denied("super admin can't grant super admin by editing profiles either", SA,
       "update profiles set role = 'super_admin', lab_id = null where id = %s", (str(U2),))
denied("staff can't edit their own role directly", R1,
       "update profiles set role = 'lab_admin' where id = %s", (str(R1),))
denied("owner can't manage another lab's staff", A1, "select set_employee_role(%s, 'runner')", (str(C2),))
check("staff list shows lab only",
      len(allowed("owner lists staff", A1, "select id from lab_staff(%s)", (L1,))) == 3)

# ---------------------------------------------------------------- messaging
print("Messaging...")
conv = allowed("clerk opens chat with patient", C1, "select id from open_conversation(%s, %s)", (L1, str(U1)))[0][0]
denied("other lab can't open chat with patient", C2, "select open_conversation(%s, %s)", (L2, str(U1)))
allowed("clerk messages patient", C1, "insert into messages (conversation_id, direction, body) values (%s, 'from_patient', 'Your results are ready')", (conv,))
check("staff message goes out to patient", scalar(backend(), "select direction::text from messages where conversation_id = %s order by created_at desc limit 1", (conv,)) == "to_patient")
check("WhatsApp queued for patient", scalar(backend(), "select count(*) from whatsapp_outbox where user_id = %s and kind = 'lab_message'", (str(U1),)) == 1)
check("order updates queued on WhatsApp", scalar(backend(), "select count(*) from whatsapp_outbox where user_id = %s and kind = 'order_update'", (str(U1),)) >= 3)
check("patient reads message", bool(allowed("patient reads chat", U1, "select id from messages where conversation_id = %s", (conv,))))
check("other lab can't read chat", not allowed("clerk 2 reads chat", C2, "select id from messages where conversation_id = %s", (conv,)))
denied("staff can't read outbox (has no phone but still)", C1, "select * from whatsapp_outbox")
mid = allowed("WhatsApp reply lands in chat", None, "select record_whatsapp_inbound('+964 770 000 0001', 'Thanks!', 'wamid.1')", role="service_role")[0][0]
check("reply routed to the right conversation", mid is not None)
dup = allowed("duplicate WhatsApp delivery", None, "select record_whatsapp_inbound('9647700000001', 'Thanks!', 'wamid.1')", role="service_role")[0][0]
check("duplicate delivery ignored", dup is None)
denied("patients can't inject WhatsApp messages", U1, "select record_whatsapp_inbound('9647700000002', 'x', 'w2')")
claimed = allowed("dispatcher claims outbox", None, "select id from claim_whatsapp_outbox(100)", role="service_role")
claimed2 = allowed("second dispatcher run", None, "select id from claim_whatsapp_outbox(100)", role="service_role")
check("two dispatcher runs never send the same message", len(claimed) > 0 and len(claimed2) == 0)

# ---------------------------------------------------------------- earnings
print("Earnings...")
rows = allowed("owner sees earnings", A1, "select lab_id, commission_iqd from lab_earnings(now() - interval '1 day', now() + interval '1 day')")
check("owner sees only own lab earnings", len(rows) == 1 and str(rows[0][0]) == str(L1) and rows[0][1] == 1500)
check("super admin sees all labs", len(allowed("super admin earnings", SA, "select * from lab_earnings(now() - interval '1 day', now() + interval '1 day')")) == 2)
denied("patient sees no earnings", U1, "select * from lab_earnings(now() - interval '1 day', now() + interval '1 day')")

allowed("owner removes employee", A1, "select remove_employee(%s)", (str(R1),))
check("removed employee loses lab access",
      not allowed("ex-runner lists orders", R1, "select id from orders where lab_id = %s", (L1,)))

print()
print(f"{passed} passed, {len(failures)} failed")
sys.exit(1 if failures else 0)
