from django.shortcuts import get_object_or_404, redirect, render

from .models import Task


def index(request):
    if request.method == "POST":
        title = request.POST.get("title", "").strip()
        if title:
            Task.objects.create(title=title)
        return redirect("index")
    return render(request, "todos/index.html", {"tasks": Task.objects.all()})


def toggle(request, pk):
    task = get_object_or_404(Task, pk=pk)
    task.done = not task.done
    task.save(update_fields=["done"])
    return redirect("index")


def delete(request, pk):
    get_object_or_404(Task, pk=pk).delete()
    return redirect("index")


def healthz(request):
    """Liveness/readiness probe endpoint for Kubernetes (Lab 4)."""
    from django.http import JsonResponse

    return JsonResponse({"status": "ok"})
