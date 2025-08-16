from django.urls import path
from django.http import JsonResponse

def healthz(_req):
    return JsonResponse({"status": "ok"}, status=200)

urlpatterns = [
    path("healthz", healthz),
]
