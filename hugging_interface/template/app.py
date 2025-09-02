from flask import Flask, render_template, request, session, redirect, url_for, flash, jsonify
import requests
from huggingface_hub import snapshot_download
from threading import Thread
from uuid import uuid4
from diskcache import Cache
import os

class PrefixMiddleware:
    def __init__(self, app, prefix):
        self.app = app
        self.prefix = prefix.rstrip("/")
        print(f">>> PrefixMiddleware initialized with prefix: '{self.prefix}'")

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO", "")
        print(f">>> PrefixMiddleware incoming PATH_INFO: {path}")

        if path.startswith(self.prefix):
            stripped = path[len(self.prefix):] or "/"
            environ["PATH_INFO"] = stripped
            print(f">>> PATH_INFO rewritten to: {stripped}")
            return self.app(environ, start_response)
        else:
            print(">>> PrefixMiddleware rejected path:", path)
            start_response("404 Not Found", [("Content-Type", "text/plain")])
            return [b"This URL is not handled by the app."]


app = Flask(__name__)

prefix = os.environ.get("OOD_PWD_PREFIX")  # This should be set in your script.sh.erb
if prefix:
    app.wsgi_app = PrefixMiddleware(app.wsgi_app, prefix)
else:
    print(">>> OOD_PWD_PREFIX not set — expect 404s under /node/...")

# Optional: confirm routing
@app.before_request
def log_path():
    print(f">>> Request received: {request.path}")

app.secret_key = os.urandom(24)

API_URL_MODELS = "https://huggingface.co/api/models"
API_URL_DATASETS = "https://huggingface.co/api/datasets"

ALLOWED_DOWNLOAD_DIRS = [f"/scratch/user/{os.environ['USER']}"]

size_cache = Cache("./size_cache")
progress_cache = Cache("./progress_cache")

COMMON_PIPELINE_TAGS = [
    "text-classification", "token-classification", "text-generation",
    "text2text-generation", "summarization", "question-answering",
    "translation", "fill-mask", "sentence-similarity", "conversational",
    "zero-shot-classification"
]

COMMON_LIBRARIES = [
    "transformers", "sentence-transformers", "diffusers",
    "sklearn", "peft", "keras"
]

##############################################
# UTILITIES
##############################################

def format_size(num_bytes):
    if not num_bytes or num_bytes == 0:
        return "Unknown size"
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if num_bytes < 1024:
            return f"{num_bytes:.2f} {unit}"
        num_bytes /= 1024
    return f"{num_bytes:.2f} PB"

def get_repo_size(repo_id, repo_type="model"):
    cache_key = f"{repo_type}:{repo_id}"
    if cache_key in size_cache:
        size = size_cache[cache_key]
        return size if size > 0 else None

    url = f"https://huggingface.co/api/{'models' if repo_type=='model' else 'datasets'}/{repo_id}"
    r = requests.get(url)
    total_bytes = None
    if r.status_code == 200:
        data = r.json()
        if "siblings" in data:
            total_bytes = sum(f.get("size", 0) for f in data["siblings"] if f.get("size"))
            if total_bytes > 0:
                size_cache[cache_key] = total_bytes
    return total_bytes

##############################################
# SEARCH
##############################################

def get_models(task=None, library=None, model_name_filter=None, sort=None, limit=10):
    params = {"limit": 200}
    models = []

    response = requests.get(API_URL_MODELS, params=params)
    if response.status_code == 200:
        raw_models = response.json()

        for model in raw_models:
            pipeline_tag = model.get("pipeline_tag", "").lower()
            library_name = model.get("library_name", "").lower()
            model_id = model["modelId"].lower()

            if task and task.lower() not in pipeline_tag:
                continue
            if library and library.lower() not in library_name:
                continue
            if model_name_filter and model_name_filter.lower() not in model_id:
                continue

            size_bytes = get_repo_size(model["modelId"], repo_type="model")
            model["size"] = format_size(size_bytes)

            models.append(model)
            if len(models) >= limit:
                break

        if sort == "downloads":
            models.sort(key=lambda x: x.get("downloads", 0), reverse=True)
        elif sort == "likes":
            models.sort(key=lambda x: x.get("likes", 0), reverse=True)

    return models

def get_datasets(dataset_name_filter=None, limit=10):
    params = {"limit": 200}
    datasets = []

    response = requests.get(API_URL_DATASETS, params=params)
    if response.status_code == 200:
        raw_datasets = response.json()

        for ds in raw_datasets:
            dataset_id = ds["id"].lower()

            if dataset_name_filter and dataset_name_filter.lower() not in dataset_id:
                continue

            size_bytes = get_repo_size(ds["id"], repo_type="dataset")
            ds["size"] = format_size(size_bytes)

            datasets.append(ds)
            if len(datasets) >= limit:
                break

    return datasets

##############################################
# BACKGROUND DOWNLOAD
##############################################

def download_repo_in_background(job_id, repo_id, target_dir, hf_token, repo_type):
    try:
        progress_cache[job_id] = {"status": "Starting...", "progress": 0}

        final_dir = os.path.join(target_dir, repo_id)
        os.makedirs(final_dir, exist_ok=True)

        progress_cache[job_id] = {"status": "Downloading...", "progress": 10}

        snapshot_download(
            repo_id=repo_id,
            cache_dir=final_dir,
            local_dir=final_dir,
            local_dir_use_symlinks=False,
            token=hf_token,
            repo_type=repo_type,
            tqdm_class=None
        )

        if progress_cache.get(job_id, {}).get("status") == "Cancelled":
            return

        progress_cache[job_id] = {"status": "Complete", "progress": 100}

    except Exception as e:
        progress_cache[job_id] = {"status": f"Error: {str(e)}", "progress": 0}

##############################################
# ROUTES
##############################################

@app.route("/", methods=["GET", "POST"])
def index():
    print(f">>> Received request: {request.method} {request.path}")
    models = []
    datasets = []

    task = library = model_name_filter = sort = None
    limit = 10

    if request.method == "POST":
        # Clear previous job IDs because indexes will change
        session["active_jobs"] = {}

        if request.form.get("search_type") == "model":
            task = request.form.get("task")
            library = request.form.get("library")
            model_name_filter = request.form.get("model_name")
            sort = request.form.get("sort")
            limit = int(request.form.get("limit") or 10)
            models = get_models(task, library, model_name_filter, sort, limit)

        elif request.form.get("search_type") == "dataset":
            dataset_name_filter = request.form.get("dataset_name")
            limit = int(request.form.get("dataset_limit") or 10)
            datasets = get_datasets(dataset_name_filter, limit)

    # If not POST, retain previous jobs (GET reloads or fresh loads)
    active_jobs = session.get("active_jobs", {})

    return render_template(
        "index.html",
        models=models,
        datasets=datasets,
        selected_task=task,
        selected_library=library,
        selected_model_name=model_name_filter,
        selected_sort=sort,
        selected_limit=limit,
        allowed_dirs=ALLOWED_DOWNLOAD_DIRS,
        pipeline_tags=COMMON_PIPELINE_TAGS,
        libraries=COMMON_LIBRARIES,
        active_jobs=active_jobs,
        prefix=prefix
    )

@app.route("/set_credentials", methods=["GET", "POST"])
def set_credentials():
    prefix = os.environ.get("OOD_PWD_PREFIX", "")
    if request.method == "POST":
        session["hf_username"] = request.form.get("username")
        session["hf_token"] = request.form.get("token")
        flash("Credentials saved!", "success")
        return redirect(prefix + url_for("index"))

    return render_template("credentials.html", prefix=prefix)

##############################################
# DOWNLOAD STARTERS
##############################################

def save_job_id(index_key, job_id):
    active = session.get("active_jobs", {})
    active[index_key] = job_id
    session["active_jobs"] = active

@app.route("/start_download_model", methods=["POST"])
def start_download_model():
    model_id = request.form.get("model_id")
    target_dir = request.form.get("target_dir")
    hf_token = session.get("hf_token")
    index = request.form.get("index")

    job_id = str(uuid4())

    if not hf_token:
        return jsonify({"error": "No Hugging Face token found."})

    if target_dir not in ALLOWED_DOWNLOAD_DIRS:
        return jsonify({"error": "Selected directory is not allowed."})

    save_job_id(f"model-{index}", job_id)

    thread = Thread(target=download_repo_in_background, args=(
        job_id, model_id, target_dir, hf_token, "model"
    ))
    thread.start()

    return jsonify({"job_id": job_id})

@app.route("/start_download_dataset", methods=["POST"])
def start_download_dataset():
    dataset_id = request.form.get("dataset_id")
    target_dir = request.form.get("target_dir")
    hf_token = session.get("hf_token")
    index = request.form.get("index")

    job_id = str(uuid4())

    if not hf_token:
        return jsonify({"error": "No Hugging Face token found."})

    if target_dir not in ALLOWED_DOWNLOAD_DIRS:
        return jsonify({"error": "Selected directory is not allowed."})

    save_job_id(f"dataset-{index}", job_id)

    thread = Thread(target=download_repo_in_background, args=(
        job_id, dataset_id, target_dir, hf_token, "dataset"
    ))
    thread.start()

    return jsonify({"job_id": job_id})

##############################################
# PROGRESS + CANCEL
##############################################

@app.route("/download_progress/<job_id>")
def download_progress(job_id):
    return jsonify(progress_cache.get(job_id, {"status": "Unknown", "progress": 0}))

@app.route("/cancel_download/<job_id>", methods=["POST"])
def cancel_download(job_id):
    progress_cache[job_id] = {"status": "Cancelled", "progress": 0}
    return jsonify({"status": "cancelled"})
