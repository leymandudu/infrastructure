output "api_endpoint" {
  description = "Contact form API endpoint URL — set this as VITE_CONTACT_API_URL in the YusmojSolutions repo"
  value       = "${aws_apigatewayv2_api.contact.api_endpoint}/contact"
}
