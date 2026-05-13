# Requires to install redivis in the environment.
# First time you run this, it will ask you to web auth on redivis and create an account
import redivis

from pathlib import Path
current_path = Path(__file__).parent.resolve()

user = redivis.user("sdss_data_repository")
dataset = user.dataset("mosaiks:8bqm:v1_0")
table = dataset.table("1_x_1_deg_grid:m36e")

table.download_files(Path(current_path,"../input/mosaiks_1_00"))

# Uncomment the following to get 0.25 degree embeddings
# user = redivis.user("sdss_data_repository")
# dataset = user.dataset("mosaiks:8bqm:v1_0")
# table = dataset.table("0_25_x_0_25_deg_grid:76p8")
# # This table contains file references, to download:
# table.download_files(Path(current_path,"../input/mosaiks_0_25"))
