const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { FieldValue } = require("firebase-admin/firestore");

initializeApp();

const CONTACT_SUPPORT_EMAIL = "jamiremkanneh@gmail.com";

async function sendContactEmail(data) {
  const publicKey = process.env.EMAILJS_PUBLIC_KEY;
  const privateKey = process.env.EMAILJS_PRIVATE_KEY;
  const serviceId = process.env.EMAILJS_SERVICE_ID;
  const templateId = process.env.EMAILJS_TEMPLATE_ID;
  const supportEmail = CONTACT_SUPPORT_EMAIL;

  if (!publicKey || !privateKey || !serviceId || !templateId) {
    return {
      ok: false,
      error: "EmailJS is not configured on the server.",
    };
  }

  const response = await fetch("https://api.emailjs.com/api/v1.0/email/send", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      lib_version: "4.0.0",
      user_id: publicKey,
      accessToken: privateKey,
      service_id: serviceId,
      template_id: templateId,
      template_params: {
        name: data.name || "",
        email: data.email || "",
        to_email: supportEmail,
        to: supportEmail,
        reply_to: data.email || "",
        from_email: data.email || "",
        title: data.title || "New message from VOX App",
        message_phone: data.phone || "",
        subject: data.subject || "",
        message: data.message || "",
        reply_preference: data.replyPreference || "",
      },
    }),
  });

  const body = await response.text();
  if (response.status === 200) {
    return { ok: true };
  }
  return { ok: false, error: `${response.status}: ${body}`.slice(0, 500) };
}

exports.deliverContactMessage = onDocumentCreated(
  {
    document: "contact_messages/{messageId}",
    region: "us-central1",
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;

    const data = snap.data();
    if (data.emailDeliveryStatus === "sent") return;

    try {
      const result = await sendContactEmail(data);
      if (result.ok) {
        await snap.ref.update({
          emailDeliveryStatus: "sent",
          emailDeliveredAt: FieldValue.serverTimestamp(),
        });
        return;
      }

      await snap.ref.update({
        emailDeliveryStatus: "failed",
        emailDeliveryError: result.error || "Unknown error",
        emailDeliveredAt: FieldValue.serverTimestamp(),
      });
    } catch (error) {
      await snap.ref.update({
        emailDeliveryStatus: "failed",
        emailDeliveryError: String(error).slice(0, 500),
        emailDeliveredAt: FieldValue.serverTimestamp(),
      });
    }
  },
);
